alter function public.procurement_connection_status() set schema procurement_private;
create function public.procurement_connection_status() returns jsonb language sql security invoker set search_path='' as $$select procurement_private.procurement_connection_status()$$;
revoke all on function public.procurement_connection_status() from public,anon;
grant execute on function public.procurement_connection_status() to authenticated;
