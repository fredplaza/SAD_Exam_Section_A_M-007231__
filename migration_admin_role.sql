-- Run once in Supabase SQL Editor to upgrade the existing two-role schema.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('scholar','staff','admin'));

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where auth_id=auth.uid() and role in ('staff','admin')) $$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where auth_id=auth.uid() and role='admin') $$;

create or replace function public.set_profile_role(p_profile_id uuid, p_role text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'Admin only'; end if;
  if p_role is null or p_role not in ('scholar','staff','admin') then raise exception 'Invalid role'; end if;
  if p_profile_id = my_pid() then raise exception 'You cannot change your own role'; end if;
  update profiles set role=p_role where id=p_profile_id;
  if not found then raise exception 'Profile not found'; end if;
end $$;

revoke all on function public.set_profile_role(uuid,text) from public, anon;
grant execute on function public.set_profile_role(uuid,text) to authenticated;