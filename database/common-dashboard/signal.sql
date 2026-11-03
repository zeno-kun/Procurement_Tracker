-- Only a change counter is replicated; no employee or business rows are published.
create schema if not exists trackers_private;
revoke all on schema trackers_private from public,anon,authenticated;
grant usage on schema trackers_private to service_role;
create table trackers_private.change_signal(id boolean primary key default true check(id),revision bigint not null default 0,changed_at timestamptz not null default now());
insert into trackers_private.change_signal(id) values(true);
alter table trackers_private.change_signal enable row level security;
revoke all on trackers_private.change_signal from public,anon,authenticated;
grant select on trackers_private.change_signal to service_role;
create function trackers_private.signal_change() returns trigger language plpgsql security definer set search_path='' as $$
begin update trackers_private.change_signal set revision=revision+1,changed_at=clock_timestamp() where id=true;return null;end$$;
revoke all on function trackers_private.signal_change() from public,anon,authenticated;
alter publication supabase_realtime add table trackers_private.change_signal;
