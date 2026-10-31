-- Run as a database administrator. Synthetic data is always rolled back.
begin;
select set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'email','vidit@brightbots.in','role','authenticated','amr',jsonb_build_array(jsonb_build_object('method','oauth')))::text,true);
set local role authenticated;
do $$ declare r jsonb;begin
 r:=public.submit_procurement_request(gen_random_uuid(),'{"project":"ROLLBACK E2E QA","items":[{"name":"Synthetic test A","quantity":2,"required_by":"2026-11-15"},{"name":"Synthetic test B","quantity":1,"required_by":"2026-11-15"}]}');
 perform set_config('qa.request_key',r->>'request_id',true);
end $$;
reset role;
-- Invoice upload authorization fixture only: no file is sent to Google.
insert into public.procurement_files(item_id,stage,field_key,drive_file_id,filename,mime_type,size_bytes,uploaded_by)
select i.id,'Invoice','Invoice File URL','QA-NOT-A-REAL-FILE-'||i.id,'synthetic.pdf','application/pdf',10,e.id
from public.request_items i cross join public.employees e where i.request_id=current_setting('qa.request_key') and e.email='ankesh.k@brightbots.in';
set local role authenticated;
do $$
declare st text; email text; patch jsonb; items jsonb; ids uuid[]; result jsonb; again jsonb; token uuid; common jsonb; expected text; v integer;begin
 select array_agg(id) into ids from public.request_items where request_id=current_setting('qa.request_key');
 select jsonb_agg(jsonb_build_object('id',id,'version',version,'fields',jsonb_build_object('Request Approval Status','Approved'))) into items from public.request_items where id=any(ids);
 begin perform public.apply_procurement_stage('Request Approval',items,'{}',gen_random_uuid());raise exception 'Wrong owner accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'email','ramesh@brightbots.in','role','authenticated','amr',jsonb_build_array(jsonb_build_object('method','oauth')))::text,true);
 begin perform public.apply_procurement_stage('Request Approval',jsonb_build_array(items->0),'{}',gen_random_uuid());raise exception 'Partial request approval accepted';exception when invalid_parameter_value then null;end;
 begin perform public.apply_procurement_stage('Request Approval',jsonb_set(items,'{0,version}','0'),'{}',gen_random_uuid());raise exception 'Stale version accepted';exception when serialization_failure then null;end;
 begin perform public.apply_procurement_stage('Request Approval',jsonb_set(items,'{0,fields,PO Amount}','999'),'{}',gen_random_uuid());raise exception 'Cross-stage field accepted';exception when invalid_parameter_value then null;end;
 for st,email,expected in select * from (values
 ('Request Approval','ramesh@brightbots.in','Quotation'),('Quotation','amit.k@brightbots.in','Vendor Approval'),
 ('Vendor Approval','vinay@brightbots.in','PO'),('PO','amit.k@brightbots.in','Fund Approval'),
 ('Fund Approval','vinay@brightbots.in','Payment'),('Payment','ankesh.k@brightbots.in','Dispatch'),
 ('Dispatch','amit.k@brightbots.in','QC'),('QC','amandeep@brightbots.in','Invoice'),
 ('Invoice','ankesh.k@brightbots.in','Accounting'),('Accounting','ankesh.k@brightbots.in','Completed')) x loop
 perform set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'email',email,'role','authenticated','amr',jsonb_build_array(jsonb_build_object('method','oauth')))::text,true);
 patch:=case st
 when 'Request Approval' then '{"Request Approval Status":"Approved"}'::jsonb
 when 'Quotation' then '{"Vendor 1 Name":"Synthetic vendor","Vendor 1 Quote Amount":"100","Vendor 1 Courier Charges":"5","Recommended Vendor":"Synthetic vendor"}'::jsonb
 when 'Vendor Approval' then '{"Approval Status":"Approved","Approved Vendor Type":"Vendor 1"}'::jsonb
 when 'PO' then '{"PO Number":"QA-ONLY","GST %":"18"}'::jsonb
 when 'Fund Approval' then '{"Fund Approval Status":"Approved"}'::jsonb
 when 'Payment' then '{"Payment Status":"Partially Paid"}'::jsonb
 when 'Dispatch' then '{"Dispatch Status":"Delivered","Dispatch Date":"2026-10-31"}'::jsonb
 when 'QC' then '{"QC Status":"Passed","Accepted Count":"1","Rejected Count":"0"}'::jsonb
 when 'Invoice' then '{"Invoice Status":"Received","Invoice Amount":"100"}'::jsonb
 else '{"Accounting Status":"Completed","Payment Entry Number":"QA-ONLY"}'::jsonb end;
 select jsonb_agg(jsonb_build_object('id',i.id,'version',i.version,'fields',patch||case when st='Invoice' then jsonb_build_object('Invoice File URL','https://drive.google.com/file/d/QA-NOT-A-REAL-FILE-'||i.id||'/view') else '{}'::jsonb end) order by i.id) into items from public.request_items i where i.id=any(ids);
 if jsonb_array_length(items)<>2 then raise exception 'Stage owner cannot read the selected items: %',st;end if;
 common:=case when st='Payment' then '{"advance_amount":"50"}'::jsonb else '{}'::jsonb end;
 token:=gen_random_uuid();result:=public.apply_procurement_stage(st,items,common,token);
 if result->>'updated'<>'2' or exists(select 1 from jsonb_array_elements(result->'items')x where x->>'stage'<>expected) then raise exception 'Wrong transition from %: %',st,result;end if;
 again:=public.apply_procurement_stage(st,items,common,token);if again<>result then raise exception 'Retry was not idempotent';end if;
 end loop;
end $$;
reset role;
do $$begin
 if (select count(*) from public.request_items where request_id=current_setting('qa.request_key') and current_stage='Completed' and version=11)<>2 then raise exception 'Final versions wrong';end if;
 if (select sum((data->>'Advance Amount')::numeric) from public.request_items where request_id=current_setting('qa.request_key'))<>50 then raise exception 'Payment allocation wrong';end if;
 if (select sum((data->>'Total Amount With GST')::numeric) from public.request_items where request_id=current_setting('qa.request_key'))<>365.8 then raise exception 'PO/GST calculation wrong';end if;
 if (select count(*) from public.procurement_mail_outbox where request_id=current_setting('qa.request_key'))<>11 then raise exception 'Duplicate or missing queued notification';end if;
 if (select count(*) from public.audit_events a join public.request_items i on i.id=a.item_id where i.request_id=current_setting('qa.request_key') and a.action like 'stage_action:%')<>20 then raise exception 'Missing action audit';end if;
end $$;
rollback;
select 'PASS: complete 10-stage two-item journey; assigned owners, whole-request approval, version conflicts, field whitelist, idempotency, server PO/GST, partial-payment allocation, file references, audit and email deduplication. All fixtures rolled back.' as verification;
