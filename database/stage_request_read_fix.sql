create function procurement_private.can_read_request(p_request text) returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and exists(select 1 from public.request_items i join public.stage_owners s on s.stage=i.current_stage join public.employees e on e.id=s.employee_id where i.request_id=p_request and e.email=auth.jwt()->>'email' and e.is_active)
$$;
revoke all on function procurement_private.can_read_request(text) from public,anon;
grant execute on function procurement_private.can_read_request(text) to authenticated;
alter policy request_stage_owner_read on public.requests using(procurement_private.can_read_request(id));
