-- Stage mutations are deliberately private, authenticated, row-locked and field-whitelisted.
-- No browser gets general UPDATE/DELETE privileges.
create schema if not exists procurement_private;
revoke all on schema procurement_private from public,anon;
grant usage on schema procurement_private to authenticated,service_role;
create table public.procurement_files (
 id uuid primary key default gen_random_uuid(), item_id uuid not null references public.request_items(id),
 stage text not null, field_key text not null, drive_file_id text not null unique,
 filename text not null, mime_type text not null, size_bytes bigint not null check(size_bytes between 1 and 10485760),
 uploaded_by uuid not null references public.employees(id), created_at timestamptz not null default now()
);
alter table public.procurement_files enable row level security;
revoke all on public.procurement_files from public,anon,authenticated;
grant select on public.procurement_files to authenticated;
grant all on public.procurement_files to service_role;
create index procurement_files_item_idx on public.procurement_files(item_id);
create policy file_record_read on public.procurement_files for select to authenticated using(exists(select 1 from public.request_items i where i.id=procurement_files.item_id));
create table public.procurement_mail_outbox (
 id uuid primary key default gen_random_uuid(), event_key text not null unique,
 request_id text not null references public.requests(id), actor_id uuid references public.employees(id),
 recipients text[] not null, cc text[] not null default '{}', subject text not null, message text not null,
 status text not null default 'pending' check(status in ('pending','sending','sent','failed','uncertain')),
 attempts integer not null default 0, next_attempt_at timestamptz not null default now(),
 locked_at timestamptz, provider_message_id text,last_error text,created_at timestamptz not null default now(),sent_at timestamptz
);
alter table public.procurement_mail_outbox enable row level security;
revoke all on public.procurement_mail_outbox from public,anon,authenticated;
grant all on public.procurement_mail_outbox to service_role;
create index procurement_mail_pending_idx on public.procurement_mail_outbox(status,next_attempt_at);
create policy item_stage_owner_read on public.request_items for select to authenticated using(exists(select 1 from public.stage_owners s join public.employees e on e.id=s.employee_id where s.stage=request_items.current_stage and e.email=((select auth.jwt())->>'email') and e.is_active));
create policy request_stage_owner_read on public.requests for select to authenticated using(exists(select 1 from public.request_tracking t join public.stage_owners s on s.stage=t.current_stage join public.employees e on e.id=s.employee_id where t.request_id=requests.id and e.email=((select auth.jwt())->>'email') and e.is_active));

create function procurement_private.enqueue_stage_mail(p_request text,p_stage text,p_actor uuid,p_key text,p_message text) returns void language plpgsql security definer set search_path='' as $$
declare dest text[]; requester text;
begin
 select requester_email into requester from public.requests where id=p_request;
 if p_stage in ('Rejected','Completed') then dest:=array[requester];
 else select array_agg(distinct e.email) into dest from public.stage_owners s join public.employees e on e.id=s.employee_id where s.stage=p_stage and e.is_active; end if;
 if coalesce(cardinality(dest),0)=0 then raise exception 'No enabled owner configured for stage %',p_stage;end if;
 insert into public.procurement_mail_outbox(event_key,request_id,actor_id,recipients,cc,subject,message)
 values(p_key,p_request,p_actor,dest,case when 'deepali.singh@brightbots.in'=any(dest) then '{}'::text[] else array['deepali.singh@brightbots.in'] end,
 'Procurement Tracker | '||p_stage||' | '||p_request,p_message) on conflict(event_key) do nothing;
end $$;
revoke all on function procurement_private.enqueue_stage_mail(text,text,uuid,text,text) from public,anon,authenticated;
create function procurement_private.new_request_mail() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.action='request_created' and new.after_data->>'Created via'='procurement_app' then
 perform procurement_private.enqueue_stage_mail(new.after_data->>'Request ID','Request Approval',new.actor_id,'created:'||(new.after_data->>'Request ID'),'New request from '||(new.after_data->>'Requester Name')||' for '||(new.after_data->>'Project/Client Name')||'. Please review the requested items in Procurement.');
 end if;return new;
end $$;
revoke all on function procurement_private.new_request_mail() from public,anon,authenticated;
create trigger procurement_request_mail after insert on public.audit_events for each row execute function procurement_private.new_request_mail();

create function procurement_private.nonnegative(v text,label text) returns numeric language plpgsql immutable set search_path='' as $$
declare n numeric;begin
 begin n:=coalesce(nullif(v,''),'0')::numeric;exception when others then raise exception 'Invalid %',label using errcode='22023';end;
 if not(n>=0 and n<=1000000000000) then raise exception 'Invalid %',label using errcode='22023';end if;return n;
end $$;
revoke all on function procurement_private.nonnegative(text,text) from public,anon,authenticated;
create function procurement_private.work_hours(a timestamptz,b timestamptz) returns numeric language sql stable set search_path='' as $$
 select case when a is null or b<a then null else round(count(*)::numeric/4,2) end
 from generate_series(a,b-interval '1 microsecond',interval '15 minutes') as t
 where extract(dow from t at time zone 'Asia/Kolkata')<>0
 and not(extract(dow from t at time zone 'Asia/Kolkata')=6 and extract(day from t at time zone 'Asia/Kolkata') between 8 and 14)
 and (t at time zone 'Asia/Kolkata')::time>=time '09:30' and (t at time zone 'Asia/Kolkata')::time<time '17:30';
$$;
revoke all on function procurement_private.work_hours(timestamptz,timestamptz) from public,anon,authenticated;

create function procurement_private.apply_stage_action(p_stage text,p_items jsonb,p_common jsonb,p_token uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.employees%rowtype; i public.request_items%rowtype; line jsonb; patch jsonb; f jsonb; next_stage text; st text; stamp text; allowed text[]; k text; vendor text; vendor_n integer; rate numeric; freight numeric; base numeric; gst numeric; amount numeric; total_batch numeric:=0; paid_batch numeric:=0; allocated numeric:=0; processed_total numeric:=0; row_paid numeric; n integer:=0; item_n integer; req text; before_stage text; start_at timestamptz; hours numeric; tat numeric; event_stage text; result_ids jsonb:='[]'; existing jsonb; all_ids uuid[]; one_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first' using errcode='42501';end if;
 if not coalesce(auth.jwt()->'amr' @> '[{"method":"oauth"}]'::jsonb,false) then raise exception 'Sign in with Google to verify your identity before saving stage actions.' using errcode='42501';end if;
 select * into actor from public.employees e where e.email=auth.jwt()->>'email' and e.is_active;
 if not found then raise exception 'Employee is not enabled' using errcode='42501';end if;
 if p_token is null or jsonb_typeof(p_items) is distinct from 'array' or jsonb_typeof(p_common) is distinct from 'object' then raise exception 'Invalid stage action' using errcode='22023';end if;
 item_n:=jsonb_array_length(p_items);if item_n not between 1 and 100 then raise exception 'Select 1–100 items' using errcode='22023';end if;
 if not exists(select 1 from public.stage_owners where stage=p_stage and employee_id=actor.id) then raise exception 'Only the assigned stage owner can perform this action' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor.id::text||p_token::text,0));
 select after_data into existing from public.audit_events where actor_id=actor.id and action='stage_batch' and after_data->>'token'=p_token::text limit 1;
 if found then
 if existing->'input' is distinct from jsonb_build_object('stage',p_stage,'items',p_items,'common',p_common) then raise exception 'Retry token belongs to a different action' using errcode='22023';end if;
 return existing->'result';end if;
 select array_agg((x->>'id')::uuid order by x->>'id') into all_ids from jsonb_array_elements(p_items)x;
 if (select count(distinct x) from unnest(all_ids)x)<>item_n then raise exception 'Duplicate selected item' using errcode='22023';end if;
 -- Consistent lock order avoids races across overlapping bulk selections.
 perform 1 from public.request_items where id=any(all_ids) order by id for update;
 if p_stage='Request Approval' and exists(select 1 from public.request_items r where r.current_stage=p_stage and r.request_id in(select request_id from public.request_items where id=any(all_ids)) and not(r.id=any(all_ids))) then raise exception 'Request Approval applies to the entire request. Select all its pending items.' using errcode='22023';end if;
 if p_stage='Request Approval' and exists(select 1 from jsonb_array_elements(p_items) x join public.request_items r on r.id=(x->>'id')::uuid group by r.request_id having count(distinct x->'fields'->>'Request Approval Status')>1) then raise exception 'Use the same approval decision for all items in a request.' using errcode='22023';end if;
 if p_stage='Payment' then
 select sum(round(coalesce(nullif(ri.data->>'Total Amount With GST','')::numeric,0),2)) into total_batch from public.request_items ri join jsonb_array_elements(p_items) x on ri.id=(x->>'id')::uuid where x->'fields'->>'Payment Status'='Partially Paid';
 paid_batch:=round(procurement_private.nonnegative(p_common->>'advance_amount','advance amount'),2);
 if paid_batch>coalesce(total_batch,0) then raise exception 'Advance exceeds the selected total' using errcode='22023';end if;
 end if;
 for line in select value from jsonb_array_elements(p_items) loop
 n:=n+1;select * into i from public.request_items where id=(line->>'id')::uuid;
 if not found or i.current_stage<>p_stage or i.version is distinct from (line->>'version')::integer then raise exception 'An item changed. Refresh before saving.' using errcode='40001';end if;
 patch:=line->'fields';if jsonb_typeof(patch) is distinct from 'object' then raise exception 'Invalid stage fields' using errcode='22023';end if;
 allowed:=case p_stage
 when 'Request Approval' then array['Request Approval Status','Request Approval Remarks']
 when 'Quotation' then array['Vendor 1 Name','Vendor 1 Quote Amount','Vendor 1 Courier Charges','Vendor 1 Quote File URL','Vendor 2 Name','Vendor 2 Quote Amount','Vendor 2 Courier Charges','Vendor 2 Quote File URL','Vendor 3 Name','Vendor 3 Quote Amount','Vendor 3 Courier Charges','Vendor 3 Quote File URL','Recommended Vendor','Quotation Remarks','Vendor Item Shipped Date']
 when 'Vendor Approval' then array['Approval Status','Approval Remarks','Approved Vendor Type']
 when 'PO' then array['PO Number','GST %','PO File URL','PO Remarks']
 when 'Fund Approval' then array['Fund Approval Status','Fund Approval Remarks']
 when 'Payment' then array['Payment Policy','Payment Status','Payment Remarks']
 when 'Dispatch' then array['Dispatch Status','Dispatch Date','Transport / Courier Name','Tracking / LR Number','Dispatch Remarks']
 when 'QC' then array['QC Status','QC Date','Accepted Count','Rejected Count','TC / Test Certificate File URL','Bill Received File URL','Item Photo URL','QC Remarks']
 when 'Invoice' then array['Invoice Number','Invoice Date','Invoice Amount','Invoice Status','Invoice Remarks','Invoice File URL']
 when 'Accounting' then array['Payment Entry Number','Payment Date','Payment Mode','Accounting Status','Accounting Remarks'] else null end;
 if allowed is null or patch-allowed<>'{}'::jsonb or length(patch::text)>50000 then raise exception 'Fields are not allowed for this stage' using errcode='22023';end if;
 for k in select jsonb_object_keys(patch) loop
 if jsonb_typeof(patch->k) not in ('string','number','null') or length(coalesce(patch->>k,''))>4000 then raise exception 'Invalid field value' using errcode='22023';end if;
 if k like '%File URL' or k='Item Photo URL' then
 if coalesce(patch->>k,'')<>'' and patch->>k is distinct from i.data->>k and not exists(select 1 from public.procurement_files a where a.item_id=i.id and a.stage=p_stage and a.field_key=k and a.uploaded_by=actor.id and 'https://drive.google.com/file/d/'||a.drive_file_id||'/view'=patch->>k) then raise exception 'Upload the file through Procurement first' using errcode='22023';end if;
 end if;
 if k like '% Date' and coalesce(patch->>k,'')<>'' then perform (patch->>k)::date;end if;
 end loop;
 f:=i.data||patch;next_stage:=p_stage;stamp:=case p_stage when 'Vendor Approval' then 'Approval Timestamp' else p_stage||' Timestamp' end;
 case p_stage
 when 'Request Approval' then
 st:=f->>'Request Approval Status';if st not in ('Approved','Rejected') or st is null then raise exception 'Choose Approved or Rejected' using errcode='22023';end if;
 next_stage:=case st when 'Approved' then 'Quotation' else 'Rejected' end;f:=f||jsonb_build_object('Request Approved By',actor.email);
 when 'Quotation' then
 for vendor_n in 1..3 loop
 rate:=procurement_private.nonnegative(f->>('Vendor '||vendor_n||' Quote Amount'),'quote rate');freight:=procurement_private.nonnegative(f->>('Vendor '||vendor_n||' Courier Charges'),'courier charges');
 f:=f||jsonb_build_object('Vendor '||vendor_n||' Quote Amount',rate,'Vendor '||vendor_n||' Courier Charges',freight);
 end loop;
 if not exists(select 1 from generate_series(1,3) v where length(btrim(coalesce(f->>('Vendor '||v||' Name'),'')))>0) then raise exception 'Enter at least one vendor' using errcode='22023';end if;
 if coalesce(f->>'Recommended Vendor','')<>'' and not (f->>'Recommended Vendor'=any(array[f->>'Vendor 1 Name',f->>'Vendor 2 Name',f->>'Vendor 3 Name'])) then raise exception 'Recommended vendor must match an entered vendor' using errcode='22023';end if;
 f:=f||jsonb_build_object('Quotation Status','Completed');next_stage:='Vendor Approval';
 when 'Vendor Approval' then
 st:=f->>'Approval Status';if st is null or st not in ('Approved','Rejected','On Hold') then raise exception 'Choose an approval status' using errcode='22023';end if;
 if st='Approved' then
 vendor:=f->>'Approved Vendor Type';if vendor not in ('Vendor 1','Vendor 2','Vendor 3') or vendor is null or length(btrim(coalesce(f->>(vendor||' Name'),'')))=0 then raise exception 'Select an available vendor for each item' using errcode='22023';end if;
 f:=f||jsonb_build_object('Approved Vendor',f->>(vendor||' Name'));next_stage:='PO';
 elsif st='Rejected' then next_stage:='Rejected';end if;
 f:=f-'Approved Vendor Type';
 when 'PO' then
 if length(btrim(coalesce(f->>'PO Number','')))=0 then raise exception 'PO number is required' using errcode='22023';end if;
 vendor:=f->>'Approved Vendor';vendor_n:=null;
 for n in 1..3 loop if f->>('Vendor '||n||' Name')=vendor then vendor_n:=n;exit;end if;end loop;
 if vendor_n is null then raise exception 'Approved vendor does not match quotation' using errcode='22023';end if;
 rate:=procurement_private.nonnegative(f->>('Vendor '||vendor_n||' Quote Amount'),'rate');freight:=procurement_private.nonnegative(f->>('Vendor '||vendor_n||' Courier Charges'),'courier');base:=round(coalesce(i.quantity,0)*rate+freight,2);
 gst:=procurement_private.nonnegative(f->>'GST %','GST');if gst>100 then raise exception 'GST must be between 0 and 100' using errcode='22023';end if;
 f:=f||jsonb_build_object('PO Amount',base,'PO Vendor Name',vendor,'GST %',gst,'GST Amount',round(base*gst/100,2),'Total Amount With GST',base+round(base*gst/100,2),'PO Status','Created','Fund Approval Status','Pending');next_stage:='Fund Approval';
 when 'Fund Approval' then
 st:=f->>'Fund Approval Status';if st is null or st not in ('Approved','Rejected','On Hold') then raise exception 'Choose a fund approval status' using errcode='22023';end if;
 next_stage:=case st when 'Approved' then 'Payment' when 'Rejected' then 'Rejected' else p_stage end;f:=f||jsonb_build_object('Fund Approved By',actor.email);
 when 'Payment' then
 st:=f->>'Payment Status';if st is null or st not in ('Paid','Partially Paid','Not Required','Pending','On Hold') then raise exception 'Choose a payment status' using errcode='22023';end if;
 amount:=round(procurement_private.nonnegative(f->>'Total Amount With GST','total'),2);
 if st in ('Paid','Not Required') then row_paid:=amount;
 elsif st='Partially Paid' then
 if paid_batch<=0 or total_batch<=0 then raise exception 'Enter the total advance for selected items' using errcode='22023';end if;
 row_paid:=round(paid_batch*(processed_total+amount)/total_batch,2)-round(paid_batch*processed_total/total_batch,2);processed_total:=processed_total+amount;allocated:=allocated+row_paid;
 else row_paid:=0;end if;
 f:=f||jsonb_build_object('Advance Amount',row_paid,'Balance Amount',greatest(amount-row_paid,0));
 if st in ('Paid','Partially Paid','Not Required') then next_stage:='Dispatch';end if;
 when 'Dispatch' then
 st:=f->>'Dispatch Status';if st is null or st not in ('Dispatched','Delivered','Pending','On Hold') then raise exception 'Choose a dispatch status' using errcode='22023';end if;
 if st in ('Dispatched','Delivered') then next_stage:='QC';end if;
 when 'QC' then
 st:=f->>'QC Status';if st is null or st not in ('Passed','Failed','On Hold') then raise exception 'Choose a QC status' using errcode='22023';end if;
 amount:=procurement_private.nonnegative(f->>'Accepted Count','accepted count');base:=procurement_private.nonnegative(f->>'Rejected Count','rejected count');
 if amount+base>coalesce(i.quantity,0) then raise exception 'QC counts exceed requested quantity' using errcode='22023';end if;
 if st='Passed' then next_stage:='Invoice';end if;
 when 'Invoice' then
 st:=f->>'Invoice Status';if st is null or st not in ('Received','Not Required') then raise exception 'Choose invoice status' using errcode='22023';end if;
 if coalesce(f->>'Invoice File URL','')='' then raise exception 'Invoice or bill upload is mandatory' using errcode='22023';end if;
 amount:=procurement_private.nonnegative(f->>'Invoice Amount','invoice amount');f:=f||jsonb_build_object('Invoice Amount',amount);next_stage:='Accounting';
 when 'Accounting' then
 if f->>'Accounting Status' is distinct from 'Completed' then raise exception 'Choose Completed' using errcode='22023';end if;next_stage:='Completed';
 else raise exception 'Unknown stage' using errcode='22023';end case;
 f:=f||jsonb_build_object(stamp,transaction_timestamp(),'Last Updated By',actor.email,'Last Updated Timestamp',transaction_timestamp());
 update public.request_items set data=f,current_stage=next_stage,version=version+1,updated_at=transaction_timestamp() where id=i.id;
 update public.request_tracking set current_stage=next_stage where item_id=i.id;
 insert into public.audit_events(item_id,actor_id,action,before_data,after_data) values(i.id,actor.id,'stage_action:'||p_stage,i.data,f);
 if next_stage<>p_stage then
 event_stage:=case when p_stage in ('Invoice','Accounting') then 'Invoice + Accounting' else p_stage end;
 start_at:=coalesce((select max(completed_at) from public.stage_events where item_id=i.id), (select requested_at from public.requests where id=i.request_id));
 if p_stage='Accounting' then select started_at into start_at from public.stage_events where item_id=i.id and stage='Invoice + Accounting';start_at:=coalesce(start_at,(select requested_at from public.requests where id=i.request_id));end if;
 hours:=procurement_private.work_hours(start_at,transaction_timestamp());tat:=case p_stage when 'Request Approval' then 8 when 'Quotation' then 24 when 'Vendor Approval' then 8 when 'PO' then 6 when 'Fund Approval' then 4 when 'Payment' then 16 when 'Dispatch' then 24 when 'QC' then 6 else 8 end;
 insert into public.stage_events(item_id,stage,started_at,completed_at,owner_ids,attribution,working_hours,tat_hours,color)
 values(i.id,event_stage,start_at,transaction_timestamp(),array[actor.id],'verified_stage_owner_action',hours,tat,case when hours is null then null when hours<=tat then 'Green' when hours<=tat+8 then 'Yellow' else 'Red' end)
 on conflict(item_id,stage) do update set completed_at=excluded.completed_at,owner_ids=excluded.owner_ids,attribution=excluded.attribution,working_hours=excluded.working_hours,color=excluded.color where public.stage_events.stage='Invoice + Accounting' and p_stage='Accounting';
 end if;
 result_ids:=result_ids||jsonb_build_array(jsonb_build_object('id',i.id,'request_id',i.request_id,'stage',next_stage,'version',i.version+1));
 end loop;
 for req,next_stage in select distinct x->>'request_id',x->>'stage' from jsonb_array_elements(result_ids)x loop
 if next_stage<>p_stage then perform procurement_private.enqueue_stage_mail(req,next_stage,actor.id,'stage:'||p_token::text||':'||req,'Procurement request '||req||' has moved from '||p_stage||' to '||next_stage||'. Please open Procurement for the item details.');end if;
 end loop;
 existing:=jsonb_build_object('items',result_ids,'updated',item_n);
 insert into public.audit_events(actor_id,action,after_data) values(actor.id,'stage_batch',jsonb_build_object('token',p_token,'input',jsonb_build_object('stage',p_stage,'items',p_items,'common',p_common),'result',existing));
 return existing;
end $$;
revoke all on function procurement_private.apply_stage_action(text,jsonb,jsonb,uuid) from public,anon;
grant execute on function procurement_private.apply_stage_action(text,jsonb,jsonb,uuid) to authenticated;
create function public.apply_procurement_stage(stage text,items jsonb,common jsonb,client_token uuid) returns jsonb language sql security invoker set search_path='' as $$select procurement_private.apply_stage_action(stage,items,common,client_token)$$;
revoke all on function public.apply_procurement_stage(text,jsonb,jsonb,uuid) from public,anon;
grant execute on function public.apply_procurement_stage(text,jsonb,jsonb,uuid) to authenticated;
insert into public.app_settings(key,value) values('integrations',jsonb_build_object('folder_id','1ovaJdB4Gyx2OUiOudt7fGxO6Ri6IIYmU','folder_name','Procurement Tracker Supabase','owner_email','deepali.singh@brightbots.in','connected',false)) on conflict(key) do nothing;
