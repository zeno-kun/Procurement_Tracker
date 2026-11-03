-- Human-facing numbers only. Primary keys and every existing reference remain unchanged.
lock table public.requests in share row exclusive mode;
alter table public.requests add column display_id text unique;
create sequence procurement_private.request_display_number;
revoke all on sequence procurement_private.request_display_number from public,anon,authenticated;
-- Keep legacy references familiar; number app-created UUID requests by creation order.
with numbered as (
 select id,requested_at,row_number() over(order by requested_at nulls first,id) n from public.requests
) update public.requests r set display_id=case when r.id ~ '^REQ-[0-9a-f]{32}-[0-9a-f]{32}$'
 then 'REQ-'||to_char(n.requested_at at time zone 'Asia/Kolkata','YYYY')||'-'||lpad(n.n::text,greatest(6,length(n.n::text)),'0') else r.id end
from numbered n where n.id=r.id;
select setval('procurement_private.request_display_number',greatest((select count(*) from public.requests),1),(select count(*)>0 from public.requests));
alter table public.requests alter column display_id set not null;
create function procurement_private.assign_request_display_id() returns trigger language plpgsql security definer set search_path='' as $$
declare serial_text text;
begin
 if new.id ~ '^REQ-[0-9a-f]{32}-[0-9a-f]{32}$' then
 serial_text:=nextval('procurement_private.request_display_number')::text;
 new.display_id:='REQ-'||to_char(coalesce(new.requested_at,transaction_timestamp()) at time zone 'Asia/Kolkata','YYYY')||'-'||lpad(serial_text,greatest(6,length(serial_text)),'0');
 else new.display_id:=new.id;end if;
 return new;
end$$;
revoke all on function procurement_private.assign_request_display_id() from public,anon,authenticated;
create trigger request_display_number before insert on public.requests for each row execute function procurement_private.assign_request_display_id();
CREATE OR REPLACE FUNCTION procurement_private.enqueue_stage_mail(p_request text, p_stage text, p_actor uuid, p_key text, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare dest text[]; requester text; request_number text;
begin
 select requester_email,coalesce(display_id,id) into requester,request_number from public.requests where id=p_request;
 if p_stage in ('Rejected','Completed') then dest:=array[requester];
 else select array_agg(distinct e.email) into dest from public.stage_owners s join public.employees e on e.id=s.employee_id where s.stage=p_stage and e.is_active; end if;
 if coalesce(cardinality(dest),0)=0 then raise exception 'No enabled owner configured for stage %',p_stage;end if;
 insert into public.procurement_mail_outbox(event_key,request_id,actor_id,recipients,cc,subject,message)
 values(p_key,p_request,p_actor,dest,case when 'deepali.singh@brightbots.in'=any(dest) then '{}'::text[] else array['deepali.singh@brightbots.in'] end,
 'Procurement Tracker | '||p_stage||' | '||request_number,replace(p_message,p_request,request_number)) on conflict(event_key) do nothing;
end $function$
;
