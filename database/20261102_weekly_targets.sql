-- Isolated weekly planning. No changes to stage actions, files, mail or Google ownership.
create table public.procurement_weekly_targets (
 week_start date not null check(extract(isodow from week_start)=1),
 stage text not null check(stage in ('Request Approval','Quotation','Vendor Approval','PO','Fund Approval','Payment','Dispatch','QC','Invoice + Accounting')),
 carry_count integer not null check(carry_count>=0),green_count integer not null check(green_count>=0),yellow_count integer not null check(yellow_count>=0),red_count integer not null check(red_count>=0),
 remarks text not null default '' check(length(remarks)<=2000),version integer not null default 1,
 updated_by uuid not null references public.employees(id),updated_at timestamptz not null default now(),
 primary key(week_start,stage),check(green_count+yellow_count+red_count=carry_count)
);
create index procurement_weekly_targets_updated_by_idx on public.procurement_weekly_targets(updated_by);
alter table public.procurement_weekly_targets enable row level security;
revoke all on public.procurement_weekly_targets from anon,authenticated;
-- Only controlled RPCs expose aggregates and versioned writes; table has no direct browser access.
create function procurement_private.weekly_can_edit(st text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.employees e where e.is_active and lower(e.email)=lower(auth.jwt()->>'email') and (
 e.email in ('deepali.singh@brightbots.in','vidit@brightbots.in','arpit.s@brightbots.in','vinay@brightbots.in','arjun@brightbots.in') or exists(select 1 from public.stage_owners s where s.employee_id=e.id and (s.stage=st or st='Invoice + Accounting' and s.stage in ('Invoice','Accounting')))));
$$;
create function procurement_private.weekly_stamp(v text) returns timestamptz language plpgsql immutable set search_path='' as $$
 begin if v !~ '^\d{4}-\d{2}-\d{2}' then return null;end if;return case when length(v)=10 then v::timestamp at time zone 'Asia/Kolkata' else v::timestamptz end;exception when others then return null;end;
$$;
create function procurement_private.weekly_intervals() returns table(item_id uuid,stage text,started_at timestamptz,completed_at timestamptz) language sql stable set search_path='' as $$
 with stages(st,keys) as (values
 ('Request Approval',array['Timestamp']),('Quotation',array['Request Approval Timestamp','Timestamp']),
 ('Vendor Approval',array['Quotation Timestamp','Request Approval Timestamp','Timestamp']),('PO',array['Approval Timestamp','Quotation Timestamp','Timestamp']),
 ('Fund Approval',array['PO Timestamp','Approval Timestamp','Timestamp']),('Payment',array['Fund Approval Timestamp','PO Timestamp','Timestamp']),
 ('Dispatch',array['Payment Timestamp','Payment Date','PO Timestamp','Timestamp']),('QC',array['Dispatch Timestamp','Dispatch Date','Payment Timestamp','Payment Date','Timestamp']),
 ('Invoice + Accounting',array['QC Timestamp','QC Date','Dispatch Timestamp','Dispatch Date','Timestamp'])),
 current_intervals as (
 select i.id, s.st,coalesce(e.started_at,(select procurement_private.weekly_stamp(i.data->>k) from unnest(s.keys) with ordinality x(k,n) where procurement_private.weekly_stamp(i.data->>k) is not null order by n limit 1)) start_at
 from public.request_items i join stages s on s.st=case when i.current_stage in ('Invoice','Accounting') then 'Invoice + Accounting' else i.current_stage end
 left join public.stage_events e on e.item_id=i.id and e.stage=s.st
 ), intervals as (
 select e.item_id,e.stage,e.started_at,e.completed_at from public.stage_events e
 where not exists(select 1 from current_intervals c where c.id=e.item_id and c.st=e.stage)
 and (e.stage<>'Invoice + Accounting' or exists(select 1 from public.request_items i where i.id=e.item_id and (i.current_stage='Completed' or procurement_private.weekly_stamp(i.data->>'Accounting Timestamp') is not null)))
 union all select c.id,c.st,c.start_at,null::timestamptz from current_intervals c
 ) select * from intervals where started_at is not null and (stage<>'Fund Approval' or started_at>='2026-06-03T00:00:00+05:30'::timestamptz);
$$;
create function procurement_private.weekly_snapshot(target_week date) returns jsonb language plpgsql stable security definer set search_path='' as $$
 declare result jsonb;
 begin
 if auth.uid() is null then raise exception 'Sign in first' using errcode='42501';end if;
 if target_week is null or extract(isodow from target_week)<>1 then raise exception 'Choose a Monday' using errcode='22023';end if;
 select jsonb_build_object('week_start',target_week,'stages',(select coalesce(jsonb_agg(jsonb_build_object('stage',st,'carry_count',(select count(distinct item_id) from procurement_private.weekly_intervals() i where i.stage=st and i.started_at<target_week::timestamp at time zone 'Asia/Kolkata' and (i.completed_at is null or i.completed_at>=target_week::timestamp at time zone 'Asia/Kolkata')),'can_edit',true)),'[]'::jsonb) from unnest(array['Request Approval','Quotation','Vendor Approval','PO','Fund Approval','Payment','Dispatch','QC','Invoice + Accounting']) s(st) where procurement_private.weekly_can_edit(st)),
 'targets',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.procurement_weekly_targets t where t.week_start=target_week and procurement_private.weekly_can_edit(t.stage)),
 'previous_targets',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.procurement_weekly_targets t where t.week_start=target_week-7 and procurement_private.weekly_can_edit(t.stage))) into result;
 return result;end;
$$;
create function procurement_private.save_weekly_targets(target_week date,entries jsonb,remarks text) returns jsonb language plpgsql security definer set search_path='' as $$
 declare actor uuid;line jsonb;old public.procurement_weekly_targets%rowtype;expected integer;carry integer;g integer;y integer;r integer;n integer:=0;st text;
 begin
 if auth.uid() is null or not coalesce(auth.jwt()->'amr' @> '[{"method":"oauth"}]'::jsonb,false) then raise exception 'Sign in with Google before saving targets' using errcode='42501';end if;
 select id into actor from public.employees where is_active and lower(email)=lower(auth.jwt()->>'email');if actor is null then raise exception 'Employee is not enabled' using errcode='42501';end if;
 if target_week is null or extract(isodow from target_week)<>1 or target_week<'2020-01-01' or target_week>'2100-12-31' then raise exception 'Invalid target week' using errcode='22023';end if;
 if jsonb_typeof(entries) is distinct from 'array' or jsonb_array_length(entries) not between 1 and 9 or length(coalesce(remarks,''))>2000 then raise exception 'Invalid weekly targets' using errcode='22023';end if;
 if (select count(distinct value->>'stage') from jsonb_array_elements(entries))<>jsonb_array_length(entries) then raise exception 'Duplicate stage target' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('weekly_targets:'||target_week::text,0));
 for line in select value from jsonb_array_elements(entries) order by value->>'stage' loop
 st:=line->>'stage';if not procurement_private.weekly_can_edit(st) then raise exception 'Only the assigned owner or existing reporting manager can save this stage target' using errcode='42501';end if;
 if jsonb_typeof(line->'counts') is distinct from 'array' or jsonb_array_length(line->'counts')<>3 or (line->>'version') !~ '^\d+$' or (line->>'carry_count') !~ '^\d+$' or exists(select 1 from jsonb_array_elements_text(line->'counts') x where x !~ '^\d+$') then raise exception 'Counts must be whole numbers' using errcode='22023';end if;
 expected:=(line->>'version')::integer;g:=(line->'counts'->>0)::integer;y:=(line->'counts'->>1)::integer;r:=(line->'counts'->>2)::integer;
 select count(distinct item_id) into carry from procurement_private.weekly_intervals() i where i.stage=st and i.started_at<target_week::timestamp at time zone 'Asia/Kolkata' and (i.completed_at is null or i.completed_at>=target_week::timestamp at time zone 'Asia/Kolkata');
 if carry<>(line->>'carry_count')::integer or g::bigint+y+r<>carry then raise exception 'Counts must match current carry forward. Refresh weekly data.' using errcode='22023';end if;
 select * into old from public.procurement_weekly_targets t where t.week_start=target_week and t.stage=st for update;
 if coalesce(old.version,0)<>expected then raise exception 'Target changed since it was loaded. Refresh weekly data.' using errcode='40001';end if;
 insert into public.procurement_weekly_targets(week_start,stage,carry_count,green_count,yellow_count,red_count,remarks,version,updated_by) values(target_week,st,carry,g,y,r,coalesce(remarks,''),expected+1,actor)
 on conflict(week_start,stage) do update set carry_count=excluded.carry_count,green_count=excluded.green_count,yellow_count=excluded.yellow_count,red_count=excluded.red_count,remarks=excluded.remarks,version=excluded.version,updated_by=excluded.updated_by,updated_at=now();
 insert into public.audit_events(actor_id,action,before_data,after_data) values(actor,'weekly_target',case when old.version is null then null else to_jsonb(old) end,jsonb_build_object('week_start',target_week,'stage',st,'carry_count',carry,'counts',line->'counts','version',expected+1,'remarks',coalesce(remarks,'')));
 n:=n+1;end loop;return jsonb_build_object('saved',n);end;
$$;
create function public.procurement_weekly_snapshot(target_week date) returns jsonb language sql security invoker set search_path='' as $$select procurement_private.weekly_snapshot(target_week)$$;
create function public.save_procurement_weekly_targets(target_week date,entries jsonb,remarks text default '') returns jsonb language sql security invoker set search_path='' as $$select procurement_private.save_weekly_targets(target_week,entries,remarks)$$;
revoke all on function procurement_private.weekly_can_edit(text),procurement_private.weekly_stamp(text),procurement_private.weekly_intervals(),procurement_private.weekly_snapshot(date),procurement_private.save_weekly_targets(date,jsonb,text),public.procurement_weekly_snapshot(date),public.save_procurement_weekly_targets(date,jsonb,text) from public,anon,authenticated;
grant execute on function procurement_private.weekly_snapshot(date),procurement_private.save_weekly_targets(date,jsonb,text),public.procurement_weekly_snapshot(date),public.save_procurement_weekly_targets(date,jsonb,text) to authenticated;
