-- Service-only Vault bridge. Never grant browser roles access to provider credentials.
create or replace function public.procurement_service_config(config jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid; saved jsonb;
begin
 select id into sid from vault.secrets where name='procurement_google_owner';
 if config is not null then
 if config->>'email' is distinct from (select value->>'owner_email' from public.app_settings where key='integrations') then raise exception 'Google account must match the configured owner';end if;
 if sid is null then sid:=vault.create_secret(config::text,'procurement_google_owner','Owner Google grant for Procurement Drive and notification sender');
 else perform vault.update_secret(sid,config::text);end if;
 update public.app_settings set value=value||jsonb_build_object('connected',true,'connected_at',now(),'sender_email',config->>'email','folder_id',config->>'folder_id') where key='integrations';
 return jsonb_build_object('connected',true);
 end if;
 if sid is null then return null;end if;
 select decrypted_secret::jsonb into saved from vault.decrypted_secrets where id=sid;
 if saved->>'email' is distinct from (select value->>'owner_email' from public.app_settings where key='integrations') then return null;end if;return saved;
end $$;
revoke all on function public.procurement_service_config(jsonb) from public,anon,authenticated;
grant execute on function public.procurement_service_config(jsonb) to service_role;
create or replace function public.procurement_claim_mail(actor uuid,request_key text default null) returns setof public.procurement_mail_outbox language sql security invoker set search_path='' as $$
 with pending as (select m.id from public.procurement_mail_outbox m where m.status in ('pending','failed') and m.next_attempt_at<=now() and (request_key is null or m.request_id=request_key) and (m.actor_id=actor or exists(select 1 from public.employees e where e.id=actor and e.email=(select value->>'owner_email' from public.app_settings where key='integrations') and e.is_active)) order by m.created_at limit 10 for update skip locked)
 update public.procurement_mail_outbox m set status='sending',locked_at=now(),attempts=attempts+1 where m.id in(select id from pending) returning m.*;
$$;
revoke all on function public.procurement_claim_mail(uuid,text) from public,anon,authenticated;
grant execute on function public.procurement_claim_mail(uuid,text) to service_role;
create or replace function procurement_private.procurement_connection_status() returns jsonb language plpgsql security definer set search_path='' as $$
declare setting jsonb;actor public.employees%rowtype;begin
 select * into actor from public.employees where email=auth.jwt()->>'email' and is_active;
 if auth.uid() is null or not found then raise exception 'Not authorized' using errcode='42501';end if;
 select value into setting from public.app_settings where key='integrations';
 if actor.email=setting->>'owner_email' then setting:=setting||jsonb_build_object('pending_mail',(select count(*) from public.procurement_mail_outbox where status in ('pending','failed')),'uncertain_mail',(select count(*) from public.procurement_mail_outbox where status in ('uncertain','sending')));end if;
 return setting;
end $$;
revoke all on function procurement_private.procurement_connection_status() from public,anon;
grant execute on function procurement_private.procurement_connection_status() to authenticated;

update public.app_settings set value=(value - 'connected_at' - 'sender_email')||jsonb_build_object('owner_email','vidit@brightbots.in','folder_id',null,'connected',false) where key='integrations';
