-- Scholarship Monitoring and Academic Compliance System (synthetic data only)
-- Run once in Supabase SQL Editor.

create table programs (
  id serial primary key,
  name text unique not null,
  max_gwa numeric(3,2) not null,
  min_units int not null,
  max_failed int not null,
  max_inc int not null,
  max_drop int not null,
  deadline timestamptz not null
);
insert into programs(name,max_gwa,min_units,max_failed,max_inc,max_drop,deadline) values
 ('Merit Scholar',1.75,18,0,0,0,'2026-10-30 17:00+08'),
 ('Community Scholar',2.25,15,0,0,1,'2026-10-30 17:00+08');

create table profiles (
  id uuid primary key default gen_random_uuid(),
  auth_id uuid unique references auth.users(id) on delete set null,
  student_id text unique not null,
  full_name text not null,
  role text not null default 'scholar' check (role in ('scholar','staff','admin'))
);

create table assignments (
  id serial primary key,
  scholar_id uuid not null unique references profiles(id),
  program_id int not null references programs(id)
);

create table submissions (
  id uuid primary key default gen_random_uuid(),
  scholar_id uuid not null references profiles(id),
  academic_year text not null,
  semester int not null check (semester in (1,2)),
  gwa numeric(3,2) not null check (gwa between 1.00 and 5.00),
  units int not null check (units >= 0),
  failed_count int not null check (failed_count >= 0),
  inc_count int not null check (inc_count >= 0),
  dropped_count int not null check (dropped_count >= 0),
  evidence_ref text not null check (length(trim(evidence_ref)) > 0),
  submitted_at timestamptz not null default now(),
  verification_status text not null default 'Pending' check (verification_status in ('Pending','Verified','Returned')),
  verification_reason text,
  compliance_result text not null default 'Not Evaluated' check (compliance_result in ('Not Evaluated','Compliant','With Deficiency')),
  compliance_reasons text[] not null default '{}',
  renewal_decision text not null default 'None' check (renewal_decision in ('None','Approved','Held')),
  decision_note text,
  unique (scholar_id, academic_year, semester)
);

create table audit_log (
  id bigserial primary key,
  submission_id uuid not null references submissions(id),
  actor_id uuid references profiles(id),
  action text not null,
  detail text,
  at timestamptz not null default now()
);

-- helpers
create function is_staff() returns boolean language sql stable security definer set search_path=public as
 $$ select exists(select 1 from profiles where auth_id=auth.uid() and role in ('staff','admin')) $$;
create function is_admin() returns boolean language sql stable security definer set search_path=public as
 $$ select exists(select 1 from profiles where auth_id=auth.uid() and role='admin') $$;
create function my_pid() returns uuid language sql stable security definer set search_path=public as
 $$ select id from profiles where auth_id=auth.uid() $$;

create function set_profile_role(p_profile_id uuid, p_role text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'Admin only'; end if;
  if p_role is null or p_role not in ('scholar','staff','admin') then raise exception 'Invalid role'; end if;
  if p_profile_id = my_pid() then raise exception 'You cannot change your own role'; end if;
  update profiles set role=p_role where id=p_profile_id;
  if not found then raise exception 'Profile not found'; end if;
end $$;

-- link signup to seeded profile (by student_id) or create a scholar profile; role is never taken from client
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare sid text := new.raw_user_meta_data->>'student_id';
begin
  if sid is not null and exists(select 1 from profiles where student_id=sid and auth_id is null) then
    update profiles set auth_id=new.id where student_id=sid;
  else
    insert into profiles(auth_id,student_id,full_name)
    values(new.id, coalesce(sid,'U-'||substr(new.id::text,1,6)), coalesce(new.raw_user_meta_data->>'full_name',new.email));
  end if;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- RLS: read-only from client; all writes go through RPCs below
alter table programs enable row level security;
alter table profiles enable row level security;
alter table assignments enable row level security;
alter table submissions enable row level security;
alter table audit_log enable row level security;
create policy p_prog on programs for select to authenticated using (true);
create policy p_prof on profiles for select to authenticated using (is_staff() or auth_id=auth.uid());
create policy p_asg  on assignments for select to authenticated using (is_staff() or scholar_id=my_pid());
create policy p_sub  on submissions for select to authenticated using (is_staff() or scholar_id=my_pid());
create policy p_log  on audit_log for select to authenticated using (
  is_staff() or exists(select 1 from submissions s where s.id=submission_id and s.scholar_id=my_pid()));
revoke insert, update, delete on all tables in schema public from anon, authenticated;

create function log_it(p_sub uuid, p_action text, p_detail text) returns void language sql security definer set search_path=public as
 $$ insert into audit_log(submission_id,actor_id,action,detail) values(p_sub,my_pid(),p_action,p_detail) $$;

-- staff: register scholar + assign program (policy is a persisted record)
create function register_scholar(p_student_id text, p_name text, p_program int) returns void
language plpgsql security definer set search_path=public as $$
declare pid uuid;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  if coalesce(trim(p_student_id),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Student ID and name are required'; end if;
  select id into pid from profiles where student_id=p_student_id;
  if pid is null then insert into profiles(student_id,full_name) values(p_student_id,p_name) returning id into pid; end if;
  insert into assignments(scholar_id,program_id) values(pid,p_program)
    on conflict (scholar_id) do update set program_id=excluded.program_id;
end $$;

-- scholar: submit or resubmit a returned record
create function submit_grades(p_ay text, p_sem int, p_gwa numeric, p_units int, p_failed int, p_inc int, p_drop int, p_evidence text)
returns submissions language plpgsql security definer set search_path=public as $$
declare me profiles; s submissions;
begin
  select * into me from profiles where auth_id=auth.uid() and role='scholar';
  if me.id is null then raise exception 'Only scholars can submit grades'; end if;
  if not exists(select 1 from assignments where scholar_id=me.id) then raise exception 'You are not assigned to a scholarship program'; end if;
  if p_gwa is null or p_gwa < 1 or p_gwa > 5 then raise exception 'GWA must be between 1.00 and 5.00'; end if;
  if p_units is null or p_units<0 or p_failed is null or p_failed<0 or p_inc is null or p_inc<0 or p_drop is null or p_drop<0
    then raise exception 'Units and counts must be non-negative integers'; end if;
  if coalesce(trim(p_evidence),'')='' then raise exception 'Grade-document reference is required'; end if;
  if p_sem not in (1,2) or coalesce(p_ay,'')='' then raise exception 'Academic year and semester are required'; end if;
  select * into s from submissions where scholar_id=me.id and academic_year=p_ay and semester=p_sem;
  if found then
    if s.verification_status <> 'Returned' then
      raise exception 'Duplicate: a submission for % semester % already exists', p_ay, p_sem; end if;
    update submissions set gwa=p_gwa, units=p_units, failed_count=p_failed, inc_count=p_inc, dropped_count=p_drop,
      evidence_ref=p_evidence, submitted_at=now(), verification_status='Pending', verification_reason=null,
      compliance_result='Not Evaluated', compliance_reasons='{}', renewal_decision='None', decision_note=null
      where id=s.id returning * into s;
    perform log_it(s.id,'Resubmitted','Corrected after return; back to Pending verification');
  else
    insert into submissions(scholar_id,academic_year,semester,gwa,units,failed_count,inc_count,dropped_count,evidence_ref)
    values(me.id,p_ay,p_sem,p_gwa,p_units,p_failed,p_inc,p_drop,p_evidence) returning * into s;
    perform log_it(s.id,'Submitted','Initial submission');
  end if;
  return s;
end $$;

create function verify_submission(p_id uuid, p_status text, p_reason text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  if p_status not in ('Verified','Returned') then raise exception 'Invalid status'; end if;
  if p_status='Returned' and coalesce(trim(p_reason),'')='' then raise exception 'A reason is required when returning evidence'; end if;
  update submissions set verification_status=p_status, verification_reason=p_reason,
    compliance_result='Not Evaluated', compliance_reasons='{}', renewal_decision='None' where id=p_id;
  perform log_it(p_id,'Verification: '||p_status,p_reason);
end $$;

create function evaluate_submission(p_id uuid) returns submissions
language plpgsql security definer set search_path=public as $$
declare s submissions; p programs; r text[] := '{}';
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  select * into s from submissions where id=p_id;
  if not found then raise exception 'Submission not found'; end if;
  if s.verification_status <> 'Verified' then raise exception 'Evidence must be Verified before evaluation'; end if;
  select pr.* into p from programs pr join assignments a on a.program_id=pr.id where a.scholar_id=s.scholar_id;
  if not found then raise exception 'Scholar has no program'; end if;
  if s.gwa > p.max_gwa then r := r || format('GWA %s exceeds maximum %s', s.gwa, p.max_gwa); end if;
  if s.units < p.min_units then r := r || format('Enrolled units %s below minimum %s', s.units, p.min_units); end if;
  if s.failed_count > p.max_failed then r := r || format('Failed subjects %s exceed allowed %s', s.failed_count, p.max_failed); end if;
  if s.inc_count > p.max_inc then r := r || format('Incomplete grades %s exceed allowed %s', s.inc_count, p.max_inc); end if;
  if s.dropped_count > p.max_drop then r := r || format('Dropped subjects %s exceed allowed %s', s.dropped_count, p.max_drop); end if;
  if s.submitted_at > p.deadline then r := r || 'Late submission (after deadline 2026-10-30 17:00 Asia/Manila)'; end if;
  update submissions set compliance_reasons=r,
    compliance_result = case when cardinality(r)=0 then 'Compliant' else 'With Deficiency' end,
    renewal_decision='None' where id=p_id returning * into s;
  perform log_it(p_id,'Evaluation: '||s.compliance_result, array_to_string(r,'; '));
  return s;
end $$;

create function decide_renewal(p_id uuid, p_decision text, p_note text) returns void
language plpgsql security definer set search_path=public as $$
declare s submissions;
begin
  if not is_staff() then raise exception 'Staff only'; end if;
  if p_decision not in ('Approved','Held') then raise exception 'Invalid decision'; end if;
  select * into s from submissions where id=p_id;
  if s.verification_status <> 'Verified' or s.compliance_result = 'Not Evaluated' then
    raise exception 'Record must be Verified and Evaluated before a renewal decision'; end if;
  if p_decision='Approved' and s.compliance_result <> 'Compliant' then
    raise exception 'Cannot approve renewal: record is not Compliant'; end if;
  update submissions set renewal_decision=p_decision, decision_note=p_note where id=p_id;
  perform log_it(p_id,'Renewal: '||p_decision,p_note);
end $$;

revoke all on function register_scholar,submit_grades,verify_submission,evaluate_submission,decide_renewal,log_it,set_profile_role from public, anon;
grant execute on function register_scholar,submit_grades,verify_submission,evaluate_submission,decide_renewal,set_profile_role to authenticated;

-- SEED (run as postgres in SQL editor; bypasses RLS). A01-A06, AY 2026-2027 Sem 1
insert into profiles(student_id,full_name) values
 ('A01','Ana Reyes'),('A02','Ben Cruz'),('A03','Carla Santos'),('A04','Dino Lopez'),('A05','Ella Tan'),('A06','Faye Gomez');
insert into assignments(scholar_id,program_id)
 select p.id, case when p.student_id in ('A01','A02','A05') then 1 else 2 end from profiles p where student_id like 'A0%';
insert into submissions(scholar_id,academic_year,semester,gwa,units,failed_count,inc_count,dropped_count,evidence_ref,submitted_at,verification_status)
select p.id,'2026-2027',1,v.g,v.u,v.f,v.i,v.d,'DOC-'||p.student_id,v.t,v.s
from profiles p join (values
 ('A01',1.75,18,0,0,0,timestamptz '2026-10-30 17:00+08','Verified'),
 ('A02',1.76,18,0,0,0,timestamptz '2026-10-29 17:00+08','Verified'),
 ('A03',2.25,15,0,0,1,timestamptz '2026-10-29 17:00+08','Verified'),
 ('A04',2.25,14,0,1,0,timestamptz '2026-10-29 17:00+08','Verified'),
 ('A05',1.50,18,1,0,0,timestamptz '2026-10-30 17:01+08','Verified'),
 ('A06',2.00,15,0,0,0,timestamptz '2026-10-29 17:00+08','Pending')
) as v(sid,g,u,f,i,d,t,s) on v.sid=p.student_id;

-- After signing up the first admin in the app, promote it in SQL Editor:
--   update profiles set role='admin' where student_id='ADMIN1';
-- Create staff similarly, or manage roles from the admin dashboard:
--   update profiles set role='staff' where student_id='STAFF1';
-- Scholar test accounts sign up with student_id A01 and A02 to link to the seeded records.
