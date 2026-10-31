-- A random, mail-only dispatcher token. Never store a Supabase API/service key here.
-- The Edge Function accepts it only for processing already-queued notification jobs.
create extension if not exists pg_cron;
create function public.procurement_mail_worker_token() returns text language sql security definer set search_path='' as $$
 select decrypted_secret from vault.decrypted_secrets where name='procurement_mail_dispatch_token';
$$;
revoke all on function public.procurement_mail_worker_token() from public,anon,authenticated;
grant execute on function public.procurement_mail_worker_token() to service_role;
create function public.register_procurement_mail_worker(worker_token text) returns void language plpgsql security definer set search_path='' as $$
declare sid uuid;begin
 if worker_token is null or worker_token !~ '^[0-9a-f]{64}$' then raise exception 'Expected a random mail-only token';end if;
 select id into sid from vault.secrets where name='procurement_mail_dispatch_token';
 if sid is null then perform vault.create_secret(worker_token,'procurement_mail_dispatch_token','Can dispatch already-queued Procurement notifications only');else perform vault.update_secret(sid,worker_token);end if;
 update public.app_settings set value=value||jsonb_build_object('worker_enabled',true,'worker_interval_minutes',5) where key='integrations';
 perform cron.schedule('procurement-mail-dispatch','*/5 * * * *',$job$
 select net.http_post(url:='https://bezpksgfxkecfpwavndz.supabase.co/functions/v1/procurement-google-services',headers:=jsonb_build_object('Content-Type','application/json','X-Procurement-Mail-Token',(select decrypted_secret from vault.decrypted_secrets where name='procurement_mail_dispatch_token')),body:='{"action":"mail_worker"}'::jsonb);
 $job$);
end $$;
revoke all on function public.register_procurement_mail_worker(text) from public,anon,authenticated;
grant execute on function public.register_procurement_mail_worker(text) to service_role;
