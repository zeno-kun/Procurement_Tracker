begin;
select set_config('qa.rounding_request','QA-ROUNDING-'||gen_random_uuid()::text,true);
insert into public.requests(id,requester_email,requester_name,project,requested_at,imported_at) values(current_setting('qa.rounding_request'),'qa@example.test','Synthetic','ROLLBACK ROUNDING QA',now(),null);
insert into public.request_items(request_id,item_name,quantity,required_by,current_stage,data) select current_setting('qa.rounding_request'),'Synthetic cent item '||n,1,'2026-11-15','Payment','{"Total Amount With GST":0.01}'::jsonb from generate_series(1,100)n;
insert into public.request_tracking(item_id,request_id,requester_email,item_name,quantity,required_by,current_stage) select id,request_id,'qa@example.test',item_name,quantity,required_by,current_stage from public.request_items where request_id=current_setting('qa.rounding_request');
select set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'email','ankesh.k@brightbots.in','role','authenticated','amr',jsonb_build_array(jsonb_build_object('method','oauth')))::text,true);
set local role authenticated;
do $$declare items jsonb;begin
 select jsonb_agg(jsonb_build_object('id',id,'version',version,'fields',jsonb_build_object('Payment Status','Partially Paid')) order by id) into items from public.request_items where request_id=current_setting('qa.rounding_request');
 perform public.apply_procurement_stage('Payment',items,'{"advance_amount":0.50}',gen_random_uuid());
end $$;
reset role;
do $$begin
 if (select sum((data->>'Advance Amount')::numeric) from public.request_items where request_id=current_setting('qa.rounding_request'))<>0.50 then raise exception 'Allocation did not preserve the exact advance';end if;
 if exists(select 1 from public.request_items where request_id=current_setting('qa.rounding_request') and ((data->>'Advance Amount')::numeric<0 or (data->>'Balance Amount')::numeric<0 or (data->>'Advance Amount')::numeric>0.01)) then raise exception 'Invalid per-item paid or balance amount';end if;
end $$;
rollback;
select 'PASS: 100 low-value items allocate a 50-paise advance exactly, without negative or excessive paid amounts. All fixtures rolled back.' as verification;
