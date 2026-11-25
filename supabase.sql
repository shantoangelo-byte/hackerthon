-- South Sudan Economic Inclusion Platform
-- Run this entire script in Supabase Dashboard > SQL Editor.
-- IMPORTANT: New users cannot make themselves admins. Assign admin role manually using the SQL near the end.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'job_seeker' check (role in ('job_seeker','employer','entrepreneur','training_provider','admin')),
  phone text,
  location text,
  bio text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    case when new.raw_user_meta_data->>'role' in ('employer','entrepreneur','training_provider')
      then new.raw_user_meta_data->>'role' else 'job_seeker' end
  ) on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Prevent users from changing their own role through profile updates.
create or replace function public.protect_profile_role()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if old.role = 'admin' then return new; end if;
  if new.role is distinct from old.role then
    raise exception 'Account roles can only be changed by a platform administrator';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_profile_role_trigger on public.profiles;
create trigger protect_profile_role_trigger before update on public.profiles
for each row execute procedure public.protect_profile_role();

create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  employer_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  company text not null,
  location text not null,
  employment_type text,
  description text not null,
  status text not null default 'pending' check(status in ('pending','published','rejected','closed')),
  created_at timestamptz not null default now()
);
create table if not exists public.applications (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  applicant_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'submitted' check(status in ('submitted','reviewing','shortlisted','rejected','accepted')),
  created_at timestamptz not null default now(),
  unique(job_id, applicant_id)
);
create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  provider text not null,
  location text,
  delivery_mode text,
  description text,
  status text not null default 'pending' check(status in ('pending','published','rejected','closed')),
  created_at timestamptz not null default now()
);
create table if not exists public.enrolments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'requested' check(status in ('requested','confirmed','completed','declined')),
  created_at timestamptz not null default now(),
  unique(course_id,user_id)
);
create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  sector text not null,
  location text,
  description text,
  status text not null default 'pending' check(status in ('pending','published','rejected')),
  created_at timestamptz not null default now()
);
create table if not exists public.opportunities (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  provider text,
  kind text not null,
  deadline date,
  description text,
  status text not null default 'pending' check(status in ('pending','published','rejected','closed')),
  created_at timestamptz not null default now()
);
create table if not exists public.resources (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  category text not null,
  summary text,
  url text,
  status text not null default 'pending' check(status in ('pending','published','rejected')),
  created_at timestamptz not null default now()
);
create table if not exists public.enquiries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  topic text,
  message text not null,
  created_at timestamptz not null default now()
);

-- Helper used by policies.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'); $$;

alter table public.profiles enable row level security;
alter table public.jobs enable row level security;
alter table public.applications enable row level security;
alter table public.courses enable row level security;
alter table public.enrolments enable row level security;
alter table public.businesses enable row level security;
alter table public.opportunities enable row level security;
alter table public.resources enable row level security;
alter table public.enquiries enable row level security;

-- Profiles
 drop policy if exists "Profiles are viewable by owner and admin" on public.profiles;
create policy "Profiles are viewable by owner and admin" on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (id=auth.uid() or public.is_admin()) with check (id=auth.uid() or public.is_admin());

-- Jobs: public can read published listings; employers manage their own; admins manage all.
drop policy if exists "Anyone reads published jobs" on public.jobs;
create policy "Anyone reads published jobs" on public.jobs for select using (status='published' or employer_id=auth.uid() or public.is_admin());
drop policy if exists "Employers create jobs" on public.jobs;
create policy "Employers create jobs" on public.jobs for insert to authenticated with check (employer_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('employer','admin')));
drop policy if exists "Employers update own jobs" on public.jobs;
create policy "Employers update own jobs" on public.jobs for update to authenticated using (employer_id=auth.uid() or public.is_admin()) with check (employer_id=auth.uid() or public.is_admin());
drop policy if exists "Employers delete own jobs" on public.jobs;
create policy "Employers delete own jobs" on public.jobs for delete to authenticated using (employer_id=auth.uid() or public.is_admin());

-- Applications: applicants see their own; employers see applications to their vacancies.
drop policy if exists "Application visibility" on public.applications;
create policy "Application visibility" on public.applications for select to authenticated using (applicant_id=auth.uid() or exists(select 1 from public.jobs j where j.id=job_id and j.employer_id=auth.uid()) or public.is_admin());
drop policy if exists "Applicants submit applications" on public.applications;
create policy "Applicants submit applications" on public.applications for insert to authenticated with check (applicant_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='job_seeker') and exists(select 1 from public.jobs j where j.id=job_id and j.status='published'));
drop policy if exists "Employers update application status" on public.applications;
create policy "Employers update application status" on public.applications for update to authenticated using (exists(select 1 from public.jobs j where j.id=job_id and j.employer_id=auth.uid()) or public.is_admin()) with check (exists(select 1 from public.jobs j where j.id=job_id and j.employer_id=auth.uid()) or public.is_admin());

-- Courses and enrolments
drop policy if exists "Anyone reads published courses" on public.courses;
create policy "Anyone reads published courses" on public.courses for select using(status='published' or provider_id=auth.uid() or public.is_admin());
drop policy if exists "Providers create courses" on public.courses;
create policy "Providers create courses" on public.courses for insert to authenticated with check(provider_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('training_provider','admin')));
drop policy if exists "Providers update courses" on public.courses;
create policy "Providers update courses" on public.courses for update to authenticated using(provider_id=auth.uid() or public.is_admin()) with check(provider_id=auth.uid() or public.is_admin());
drop policy if exists "Anyone enrolled can view own enrolments" on public.enrolments;
create policy "Anyone enrolled can view own enrolments" on public.enrolments for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.courses c where c.id=course_id and c.provider_id=auth.uid()) or public.is_admin());
drop policy if exists "Users enrol in published courses" on public.enrolments;
create policy "Users enrol in published courses" on public.enrolments for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.courses c where c.id=course_id and c.status='published'));
drop policy if exists "Providers update enrolments" on public.enrolments;
create policy "Providers update enrolments" on public.enrolments for update to authenticated using(exists(select 1 from public.courses c where c.id=course_id and c.provider_id=auth.uid()) or public.is_admin()) with check(exists(select 1 from public.courses c where c.id=course_id and c.provider_id=auth.uid()) or public.is_admin());

-- Business directory
drop policy if exists "Anyone reads published businesses" on public.businesses;
create policy "Anyone reads published businesses" on public.businesses for select using(status='published' or owner_id=auth.uid() or public.is_admin());
drop policy if exists "Entrepreneurs create business profiles" on public.businesses;
create policy "Entrepreneurs create business profiles" on public.businesses for insert to authenticated with check(owner_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('entrepreneur','admin')));
drop policy if exists "Owners update businesses" on public.businesses;
create policy "Owners update businesses" on public.businesses for update to authenticated using(owner_id=auth.uid() or public.is_admin()) with check(owner_id=auth.uid() or public.is_admin());

-- Admin-published funding opportunities and resources.
drop policy if exists "Anyone reads published opportunities" on public.opportunities;
create policy "Anyone reads published opportunities" on public.opportunities for select using(status='published' or public.is_admin());
drop policy if exists "Admins manage opportunities" on public.opportunities;
create policy "Admins manage opportunities" on public.opportunities for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "Anyone reads published resources" on public.resources;
create policy "Anyone reads published resources" on public.resources for select using(status='published' or public.is_admin());
drop policy if exists "Admins manage resources" on public.resources;
create policy "Admins manage resources" on public.resources for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Contact form may be submitted by visitors; only admins can read messages.
drop policy if exists "Visitors send enquiries" on public.enquiries;
create policy "Visitors send enquiries" on public.enquiries for insert to anon,authenticated with check(length(name) between 1 and 100 and length(email) between 3 and 160 and length(message) between 1 and 2000);
drop policy if exists "Admins read enquiries" on public.enquiries;
create policy "Admins read enquiries" on public.enquiries for select to authenticated using(public.is_admin());

-- Create a private storage bucket for optional user documents.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('user-documents','user-documents',false,5242880,array['application/pdf','image/jpeg','image/png'])
on conflict (id) do nothing;
drop policy if exists "Users upload documents to own folder" on storage.objects;
create policy "Users upload documents to own folder" on storage.objects for insert to authenticated with check(bucket_id='user-documents' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users read own documents" on storage.objects;
create policy "Users read own documents" on storage.objects for select to authenticated using(bucket_id='user-documents' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
drop policy if exists "Users delete own documents" on storage.objects;
create policy "Users delete own documents" on storage.objects for delete to authenticated using(bucket_id='user-documents' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- After creating your own account, replace THE_USER_UUID with your Auth user UUID to grant admin access.
-- update public.profiles set role='admin' where id='THE_USER_UUID';
