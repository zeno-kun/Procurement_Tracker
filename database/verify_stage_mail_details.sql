-- Read/rolled-back content tests only. No notifications are visible to the mail worker.
begin;
do $$
declare r text; a uuid; st text; k text; m public.procurement_mail_outbox; n integer; i record;
begin
 select request_id into r from public.request_items where current_stage='Vendor Approval' group by request_id having count(*)>1 limit 1;
 select id into a from public.employees where is_active and is_admin limit 1;
 assert r is not null and a is not null;
 foreach st in array array['Request Approval','Quotation','Vendor Approval','PO','Fund Approval','Payment','Dispatch','QC','Invoice','Accounting','Completed','Rejected'] loop
 k:='qa-mail-rollback:'||gen_random_uuid();
 perform procurement_private.enqueue_stage_mail(r,st,a,k,'QA transaction only');
 select * into m from public.procurement_mail_outbox where event_key=k;
 assert m.message like '%REQUEST SUMMARY%' and m.message like '%ACTION REQUIRED%' and m.message like '%NEXT STEP%';
 assert position((select coalesce(display_id,id) from public.requests where id=r) in m.message)>0;
 assert m.message not like '{%';
 if st='Vendor Approval' then
 assert m.message like '%Approved / Rejected / On Hold%';
 for i in select * from public.request_items where request_id=r and current_stage=st loop
 assert position(i.item_name in m.message)>0;
 assert position('Quantity: '||i.quantity::text in m.message)>0;
 if coalesce(i.data->>'Vendor 1 Quote File URL','')<>'' then assert position(i.data->>'Vendor 1 Quote File URL' in m.message)>0;end if;
 end loop;
 end if;
 if st='Payment' then assert m.message like '%total advance%' and m.message like '%actual payment%';end if;
 if st='QC' then assert m.message like '%accepted count%' and m.message like '%test certificate%';end if;
 if st not in ('Completed','Rejected') then
 assert (select array_agg(distinct e.email order by e.email) from public.stage_owners s join public.employees e on e.id=s.employee_id where s.stage=st and e.is_active)=(select array_agg(x order by x) from unnest(m.recipients)x);
 end if;
 perform procurement_private.enqueue_stage_mail(r,st,a,k,'Duplicate');
 assert (select count(*) from public.procurement_mail_outbox where event_key=k)=1;
 assert (select message from public.procurement_mail_outbox where event_key=k)=m.message;
 end loop;
 -- Once-per-item request creation keeps a single notification containing all current lines.
 k:='created:qa-mail-rollback:'||gen_random_uuid();
 perform procurement_private.enqueue_stage_mail(r,'Vendor Approval',a,k,'First item');
 perform procurement_private.enqueue_stage_mail(r,'Vendor Approval',a,k,'All items inserted');
 assert (select count(*) from public.procurement_mail_outbox where event_key=k)=1;
 assert (select message from public.procurement_mail_outbox where event_key=k) like '%All items inserted%';
end $$;
rollback;
