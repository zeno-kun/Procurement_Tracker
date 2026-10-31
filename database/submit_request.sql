-- Approved scope: create an enabled employee's own request and initial item,
-- tracking and audit records. No UPDATE/DELETE or approval privileges.
create policy request_create_self on public.requests for insert to authenticated
with check (
 auth.uid() is not null and requester_email = (select auth.jwt()->>'email')
 and id ~ ('^REQ-' || replace((select auth.uid())::text,'-','') || '-[0-9a-f]{32}$')
 and imported_at is null and requested_at = transaction_timestamp()
 and length(btrim(project)) between 1 and 300
 and exists(select 1 from public.employees e where e.email=requests.requester_email and e.is_active and e.full_name=requests.requester_name)
);
-- Read only newly created, own initial-stage items, not imported financial records.
create policy own_initial_item_read on public.request_items for select to authenticated
using (source_row is null and current_stage='Request Approval' and data->>'Created via'='procurement_app'
 and exists(select 1 from public.requests r where r.id=request_items.request_id and r.requester_email=(select auth.jwt()->>'email') and r.imported_at is null));
create policy item_create_self on public.request_items for insert to authenticated
with check (
 source_row is null and current_stage='Request Approval' and version=1
 and quantity > 0 and quantity <= 1000000000 and required_by between date '2000-01-01' and date '2100-12-31'
 and length(btrim(item_name)) between 1 and 1000 and length(coalesce(item_code,''))<=200
 and updated_at=transaction_timestamp()
 and data->>'Created via'='procurement_app' and data->>'Request Approval Status'='Pending'
 and data->>'Request ID'=request_id and data->>'Requester Email'=(select auth.jwt()->>'email')
 and data - array['Created via','Request ID','Requester Email','Requester Name','Project/Client Name','Timestamp','Item Name','Item Code','Quantity','Unit','Required By','Remarks','Request Approval Status'] = '{}'::jsonb
 and exists(select 1 from public.requests r where r.id=request_items.request_id and r.requester_email=(select auth.jwt()->>'email') and r.imported_at is null and r.requested_at=transaction_timestamp())
);
create policy tracking_create_self on public.request_tracking for insert to authenticated
with check (
 requester_email=(select auth.jwt()->>'email') and current_stage='Request Approval'
 and exists(select 1 from public.request_items i join public.requests r on r.id=i.request_id
 where i.id=request_tracking.item_id and i.request_id=request_tracking.request_id
 and i.item_name=request_tracking.item_name and i.quantity=request_tracking.quantity and i.required_by=request_tracking.required_by
 and r.requester_email=request_tracking.requester_email and r.imported_at is null and r.requested_at=transaction_timestamp())
);
create policy audit_create_self on public.audit_events for insert to authenticated
with check (
 action='request_created' and before_data is null and created_at=transaction_timestamp()
 and exists(select 1 from public.employees e where e.id=audit_events.actor_id and e.email=(select auth.jwt()->>'email') and e.is_active)
 and exists(select 1 from public.request_items i join public.requests r on r.id=i.request_id
 where i.id=audit_events.item_id and i.data=audit_events.after_data and i.current_stage='Request Approval'
 and r.requester_email=(select auth.jwt()->>'email') and r.imported_at is null and r.requested_at=transaction_timestamp())
);
grant insert on public.requests,public.request_items,public.request_tracking,public.audit_events to authenticated;
grant usage on sequence public.audit_events_id_seq to authenticated;

create function public.submit_procurement_request(client_token uuid,payload jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
 employee public.employees%rowtype;
 request_key text;
 line jsonb;
 line_id uuid;
 name_value text;
 code_value text;
 unit_value text;
 qty numeric;
 due date;
 project_value text;
 remarks_value text;
 fields jsonb;
 item_count integer;
 submitted_at timestamptz := transaction_timestamp();
begin
 if auth.uid() is null then raise exception 'Please sign in.' using errcode='42501'; end if;
 select * into employee from public.employees e where e.email=auth.jwt()->>'email' and e.is_active;
 if not found then raise exception 'This employee is not enabled for Procurement.' using errcode='42501'; end if;
 if client_token is null then raise exception 'A submission token is required.' using errcode='22023'; end if;
 if payload is null or jsonb_typeof(payload) is distinct from 'object'
 or jsonb_typeof(payload->'items') is distinct from 'array' then
 raise exception 'Provide a request with an items array.' using errcode='22023'; end if;
 item_count:=jsonb_array_length(payload->'items');
 project_value:=btrim(payload->>'project'); remarks_value:=coalesce(payload->>'remarks','');
 if item_count not between 1 and 100 or project_value is null or length(project_value) not between 1 and 300 or length(remarks_value)>4000 then
 raise exception 'Provide a project and 1–100 items; remarks must be at most 4000 characters.' using errcode='22023'; end if;
 -- Validate all lines before writing anything. Never accept requester or stage from the caller.
 for line in select value from jsonb_array_elements(payload->'items') loop
 if jsonb_typeof(line) is distinct from 'object' or length(coalesce(btrim(line->>'name'),'')) not between 1 and 1000
 or length(coalesce(line->>'code',''))>200 or length(coalesce(line->>'unit','Nos')) not between 1 and 50 then
 raise exception 'Each item needs a valid name, code and unit.' using errcode='22023'; end if;
 begin
 qty:=(line->>'quantity')::numeric; due:=(line->>'required_by')::date;
 exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception 'Invalid item quantity or required date.' using errcode='22023'; end;
 if qty is null or not (qty>0 and qty<=1000000000) or due is null or not (due between date '2000-01-01' and date '2100-12-31') then
 raise exception 'Provide a positive quantity up to 1 billion and a valid required date.' using errcode='22023'; end if;
 end loop;
 request_key:='REQ-'||replace(auth.uid()::text,'-','')||'-'||replace(client_token::text,'-','');
 perform pg_advisory_xact_lock(hashtextextended(request_key,0));
 if exists(select 1 from public.requests r where r.id=request_key and r.requester_email=employee.email) then
 return jsonb_build_object('request_id',request_key,'already_created',true); end if;
 insert into public.requests(id,requester_email,requester_name,project,requested_at,imported_at)
 values(request_key,employee.email,employee.full_name,project_value,submitted_at,null);
 for line in select value from jsonb_array_elements(payload->'items') loop
 line_id:=gen_random_uuid(); name_value:=btrim(line->>'name'); code_value:=btrim(coalesce(line->>'code',''));
 unit_value:=coalesce(nullif(btrim(line->>'unit'),''),'Nos'); qty:=(line->>'quantity')::numeric; due:=(line->>'required_by')::date;
 -- A selected catalog code must identify this item in column M, not legacy column A.
 if code_value<>'' and not exists(select 1 from public.catalog_items c where c.alternate_code=code_value and c.item_name=name_value) then
 raise exception 'The selected item code does not match the catalog. Select the item again.' using errcode='22023'; end if;
 fields:=jsonb_build_object('Created via','procurement_app','Request ID',request_key,'Requester Email',employee.email,'Requester Name',employee.full_name,'Project/Client Name',project_value,'Timestamp',submitted_at,'Item Name',name_value,'Item Code',code_value,'Quantity',qty,'Unit',unit_value,'Required By',due,'Remarks',remarks_value,'Request Approval Status','Pending');
 insert into public.request_items(id,request_id,item_name,item_code,quantity,required_by,current_stage,data,updated_at)
 values(line_id,request_key,name_value,nullif(code_value,''),qty,due,'Request Approval',fields,submitted_at);
 insert into public.request_tracking(item_id,request_id,requester_email,item_name,quantity,required_by,current_stage)
 values(line_id,request_key,employee.email,name_value,qty,due,'Request Approval');
 insert into public.audit_events(item_id,actor_id,action,before_data,after_data,created_at)
 values(line_id,employee.id,'request_created',null,fields,submitted_at);
 end loop;
 return jsonb_build_object('request_id',request_key,'item_count',item_count,'stage','Request Approval','already_created',false);
end;
$$;
revoke all on function public.submit_procurement_request(uuid,jsonb) from public,anon;
grant execute on function public.submit_procurement_request(uuid,jsonb) to authenticated;
