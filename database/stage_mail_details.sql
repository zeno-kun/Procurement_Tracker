-- Notification content only: preserve recipients, CC, deduplication and stage actions.
create or replace function procurement_private.enqueue_stage_mail(p_request text,p_stage text,p_actor uuid,p_key text,p_message text)
returns void language plpgsql security definer set search_path='' as $$
declare dest text[]; requester text; request_number text; payload jsonb; fields text[]; action_text text; content text;
begin
 select requester_email,coalesce(display_id,id) into requester,request_number from public.requests where id=p_request;
 if p_stage in ('Rejected','Completed') then dest:=array[requester];
 else select array_agg(distinct e.email) into dest from public.stage_owners s join public.employees e on e.id=s.employee_id where s.stage=p_stage and e.is_active; end if;
 if coalesce(cardinality(dest),0)=0 then raise exception 'No enabled owner configured for stage %',p_stage;end if;
 fields:=case p_stage
 when 'Request Approval' then array['Remarks']
 when 'Quotation' then array['Request Approval Status','Request Approval Remarks','Remarks']
 when 'Vendor Approval' then array['Vendor 1 Name','Vendor 1 Quote Amount','Vendor 1 Courier Charges','Vendor 1 Quote File URL','Vendor 2 Name','Vendor 2 Quote Amount','Vendor 2 Courier Charges','Vendor 2 Quote File URL','Vendor 3 Name','Vendor 3 Quote Amount','Vendor 3 Courier Charges','Vendor 3 Quote File URL','Recommended Vendor','Vendor Item Shipped Date','Quotation Remarks']
 when 'PO' then array['Approved Vendor','Approved Vendor Type','Approval Status','Approval Remarks','Vendor 1 Name','Vendor 1 Quote Amount','Vendor 1 Courier Charges','Vendor 1 Quote File URL','Vendor 2 Name','Vendor 2 Quote Amount','Vendor 2 Courier Charges','Vendor 2 Quote File URL','Vendor 3 Name','Vendor 3 Quote Amount','Vendor 3 Courier Charges','Vendor 3 Quote File URL']
 when 'Fund Approval' then array['Approved Vendor','PO Number','PO File URL','GST %','Total Amount With GST','PO Remarks']
 when 'Payment' then array['Approved Vendor','PO Number','PO File URL','Total Amount With GST','Fund Approval Status','Fund Approval Remarks','Payment Policy','Advance Amount','Balance Amount']
 when 'Dispatch' then array['Approved Vendor','PO Number','PO File URL','Total Amount With GST','Payment Policy','Payment Status','Advance Amount','Balance Amount','Payment Remarks','Vendor Item Shipped Date']
 when 'QC' then array['Approved Vendor','PO Number','Dispatch Status','Dispatch Date','Transport / Courier Name','Tracking / LR Number','Dispatch Remarks']
 when 'Invoice' then array['Approved Vendor','PO Number','PO File URL','Total Amount With GST','QC Status','QC Date','Accepted Count','Rejected Count','TC / Test Certificate File URL','Bill Received File URL','Item Photo URL','QC Remarks']
 when 'Accounting' then array['Approved Vendor','PO Number','Total Amount With GST','Advance Amount','Balance Amount','Invoice Number','Invoice Date','Invoice Amount','Invoice File URL','Invoice Status','Invoice Remarks']
 when 'Rejected' then array['Request Approval Status','Request Approval Remarks','Approval Status','Approval Remarks','Fund Approval Status','Fund Approval Remarks','QC Status','QC Remarks']
 else array['Approved Vendor','PO Number','Invoice Number','Accounting Status','Payment Entry Number','Payment Date','Payment Mode','Accounting Remarks'] end;
 select jsonb_build_object('format_version',1,'stage',p_stage,'request_number',request_number,'requester',r.requester_name,'project',r.project,'actor',(select full_name from public.employees where id=p_actor),'queued_at',now(),'summary',replace(p_message,p_request,request_number),'items',coalesce((select jsonb_agg(jsonb_build_object('name',i.item_name,'code',i.item_code,'quantity',i.quantity,'unit',coalesce(i.data->>'Unit','Nos'),'required_by',i.required_by,'details',coalesce((select jsonb_agg(jsonb_build_object('label',k,'value',i.data->>k) order by n) from unnest(fields) with ordinality x(k,n) where coalesce(i.data->>k,'')<>''),'[]'::jsonb)) order by i.item_name,i.id) from public.request_items i where i.request_id=p_request and i.current_stage=p_stage),'[]'::jsonb)) into payload from public.requests r where r.id=p_request;
 action_text:=case p_stage
 when 'Request Approval' then 'Review item names, quantities, required dates and project. Approve or reject the request and add remarks.'
 when 'Quotation' then 'Enter vendor names, per-item quote amounts, courier charges and each vendor quotation file. Select the recommended vendor and add shipping date / quotation remarks.'
 when 'Vendor Approval' then 'Compare vendor prices, courier charges and quotation files. Select the approved vendor, choose Approved / Rejected / On Hold and add approval remarks.'
 when 'PO' then 'Check the approved vendor. Enter PO number and GST %, attach the PO file and add PO remarks. Check the calculated total before saving.'
 when 'Fund Approval' then 'Review the PO file and total including GST. Choose Approved / Rejected / On Hold and add fund-approval remarks.'
 when 'Payment' then 'Check the PO total and fund approval. Select payment policy and status. For Partially Paid, enter the total advance and check allocation / balance. Add payment remarks. Confirm the actual payment before marking Paid.'
 when 'Dispatch' then 'Enter dispatch status, dispatch date, transport / courier name, tracking / LR number and dispatch remarks.'
 when 'QC' then 'Enter QC status and date, accepted count and rejected count. Upload test certificate, received bill and item photo as applicable, and add QC remarks.'
 when 'Invoice' then 'Enter invoice number, date, amount and Received / Not Required status. Upload the invoice file and add invoice remarks.'
 when 'Accounting' then 'Check invoice and payment. Enter payment entry number, payment date, payment mode and accounting remarks. Mark Accounting Completed after the entry is complete.'
 when 'Completed' then 'The listed items have completed procurement. No further stage action is required.'
 when 'Rejected' then 'Review the rejection decision and remarks in Procurement. This notice does not create a new request automatically.'
 else 'Open Procurement and review the request.' end;
 content:='BRIGHTBOTS | PROCUREMENT TRACKER'||E'\n'||upper(p_stage)||' | '||request_number||E'\n\nREQUEST SUMMARY\nRequest: '||request_number||E'\nProject: '||coalesce(payload->>'project','Not recorded')||E'\nRequested by: '||coalesce(payload->>'requester','Not recorded')||E'\nUpdated by: '||coalesce(payload->>'actor','Not recorded')||E'\n\nACTION REQUIRED\n'||action_text||E'\n\nUPDATE\n'||coalesce(payload->>'summary','')||E'\n\nITEMS AT THIS STAGE WHEN NOTIFIED\n'||
 coalesce((select string_agg(n::text||'. '||(item->>'name')||E'\n   Code: '||coalesce(item->>'code','Not recorded')||E'\n   Quantity: '||(item->>'quantity')||' '||(item->>'unit')||E'\n   Required by: '||coalesce(item->>'required_by','Not recorded')||E'\n'||coalesce((select string_agg('   '||(d->>'label')||': '||(d->>'value'),E'\n' order by dn) from jsonb_array_elements(item->'details') with ordinality f(d,dn)),'') ,E'\n\n' order by n) from jsonb_array_elements(payload->'items') with ordinality x(item,n)),'Open Procurement for the item list.')||E'\n\nNEXT STEP\nOpen Procurement > '||p_stage||' > '||request_number||E'\n\nThis email records the stage when queued; check the app for the latest status. Files retain their existing access permissions.';
 insert into public.procurement_mail_outbox(event_key,request_id,actor_id,recipients,cc,subject,message)
 values(p_key,p_request,p_actor,dest,case when 'deepali.singh@brightbots.in'=any(dest) then '{}'::text[] else array['deepali.singh@brightbots.in'] end,
 'Procurement | '||p_stage||' | '||request_number,content)
 on conflict(event_key) do update set message=excluded.message
 -- Creation is triggered once per inserted item; retain every line in the one queued request email.
 where p_key like 'created:%' and procurement_mail_outbox.status='pending';
end $$;
