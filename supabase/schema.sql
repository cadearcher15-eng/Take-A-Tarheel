-- Take A Tar Heel: database setup for Supabase
-- Paste this whole file into Supabase → SQL Editor → New query, then click Run.
-- It is safe to run again; it only creates what's missing and refreshes the rules.

-- ============ Who can use the site ============
-- UNC addresses (@unc.edu, @ad.unc.edu, @live.unc.edu, ...) are allowed automatically.
-- Add any other address (for example a teammate testing with Gmail) to allowed_emails.
create table if not exists public.allowed_emails (email text primary key);
-- Organizers see the Organizer tab: everyone's schedules, emails and survey comments.
create table if not exists public.organizers (email text primary key);
alter table public.allowed_emails enable row level security;
alter table public.organizers enable row level security;

create or replace function public.email_allowed(e text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(lower(e) like '%@unc.edu' or lower(e) like '%.unc.edu', false)
      or exists (select 1 from public.allowed_emails a where lower(a.email) = lower(e));
$$;

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select public.email_allowed(auth.jwt() ->> 'email');
$$;

create or replace function public.is_organizer() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.organizers o where lower(o.email) = lower(auth.jwt() ->> 'email'));
$$;

-- Block sign-ups from non-UNC addresses (unless listed in allowed_emails)
create or replace function public.enforce_unc_email() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.email_allowed(new.email) then
    raise exception 'Take A Tar Heel is for UNC students. Sign in with your UNC email.';
  end if;
  return new;
end $$;
drop trigger if exists enforce_unc_email on auth.users;
create trigger enforce_unc_email before insert on auth.users
  for each row execute function public.enforce_unc_email();

-- ============ Tables ============
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  label text not null check (char_length(label) between 1 and 40),
  year text check (char_length(year) <= 30),
  program text check (char_length(program) <= 40),
  bio text check (char_length(bio) <= 160),
  photo_path text check (char_length(photo_path) <= 200),
  updated_at timestamptz not null default now()
);

create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  driver uuid not null default auth.uid() references auth.users (id) on delete cascade,
  label text check (char_length(label) <= 40),
  car text check (char_length(car) <= 40),
  note text check (char_length(note) <= 90),
  repeat text not null check (repeat in ('MWF', 'TTh', 'once')),
  date date,
  arrive_by int not null check (arrive_by between 0 and 1439),
  return_at int check (return_at between 0 and 1439),
  from_place text not null check (char_length(from_place) <= 30),
  to_place text not null check (char_length(to_place) <= 30),
  seats int not null check (seats between 1 and 4),
  price int not null default 0 check (price between 0 and 5),
  accessible boolean not null default false,
  created_at timestamptz not null default now(),
  check (repeat <> 'once' or date is not null),
  check (return_at is null or return_at > arrive_by)
);

create table if not exists public.requests (
  ride_id uuid not null references public.rides (id) on delete cascade,
  rider uuid not null default auth.uid() references auth.users (id) on delete cascade,
  driver uuid,
  label text check (char_length(label) <= 40),
  legs text not null default 'there' check (legs in ('there', 'back', 'both')),
  status text not null default 'requested' check (status in ('requested', 'confirmed', 'declined')),
  created_at timestamptz not null default now(),
  primary key (ride_id, rider)
);

create table if not exists public.wanted (
  id uuid primary key default gen_random_uuid(),
  rider uuid not null default auth.uid() references auth.users (id) on delete cascade,
  label text check (char_length(label) <= 40),
  when_val text not null check (char_length(when_val) <= 20),
  arrive_by int not null check (arrive_by between 0 and 1439),
  from_place text check (char_length(from_place) <= 30),
  to_place text not null check (char_length(to_place) <= 30),
  created_at timestamptz not null default now()
);

-- Ratings keep no link to the ride row, so they survive when a ride is removed
create table if not exists public.ratings (
  ride_id uuid not null,
  rater uuid not null default auth.uid() references auth.users (id) on delete cascade,
  target uuid not null,
  role text not null check (role in ('driver', 'rider')),
  stars int not null check (stars between 1 and 5),
  tags text[] not null default '{}' check (cardinality(tags) <= 4),
  created_at timestamptz not null default now(),
  primary key (ride_id, rater, target)
);

create table if not exists public.schedules (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  label text check (char_length(label) <= 40),
  role text not null default 'rider' check (role in ('rider', 'driver', 'both')),
  home text check (char_length(home) <= 30),
  seats int check (seats between 1 and 4),
  email text check (char_length(email) <= 80),
  classes jsonb not null default '[]' check (jsonb_typeof(classes) = 'array' and jsonb_array_length(classes) <= 12),
  updated_at timestamptz not null default now()
);

create table if not exists public.survey (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  answers jsonb not null check (jsonb_typeof(answers) = 'object'),
  updated_at timestamptz not null default now()
);

create table if not exists public.survey_notes (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  text text not null check (char_length(text) <= 400),
  updated_at timestamptz not null default now()
);

-- A request always names the ride's real driver, starts as "requested", and can't be for your own ride
create or replace function public.prepare_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select r.driver into new.driver from public.rides r where r.id = new.ride_id;
  if new.driver is null then raise exception 'That ride no longer exists.'; end if;
  if new.driver = new.rider then raise exception 'You can''t join your own ride.'; end if;
  new.status := 'requested';
  return new;
end $$;
drop trigger if exists prepare_request on public.requests;
create trigger prepare_request before insert on public.requests
  for each row execute function public.prepare_request();

-- ============ Row level security ============
alter table public.profiles enable row level security;
alter table public.rides enable row level security;
alter table public.requests enable row level security;
alter table public.wanted enable row level security;
alter table public.ratings enable row level security;
alter table public.schedules enable row level security;
alter table public.survey enable row level security;
alter table public.survey_notes enable row level security;

-- profiles: signed-in members see everyone's; you edit your own
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select to authenticated using (public.is_member());
drop policy if exists "profiles write" on public.profiles;
create policy "profiles write" on public.profiles for insert to authenticated with check (id = auth.uid() and public.is_member());
drop policy if exists "profiles update" on public.profiles;
create policy "profiles update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid() and public.is_member());

-- rides: members see all; drivers manage their own; organizers can remove any
drop policy if exists "rides read" on public.rides;
create policy "rides read" on public.rides for select to authenticated using (public.is_member());
drop policy if exists "rides insert" on public.rides;
create policy "rides insert" on public.rides for insert to authenticated with check (driver = auth.uid() and public.is_member());
drop policy if exists "rides update" on public.rides;
create policy "rides update" on public.rides for update to authenticated using (driver = auth.uid()) with check (driver = auth.uid());
drop policy if exists "rides delete" on public.rides;
create policy "rides delete" on public.rides for delete to authenticated using (driver = auth.uid() or public.is_organizer());

-- requests: members see all (seat counts); riders create and cancel their own; drivers accept or decline
drop policy if exists "requests read" on public.requests;
create policy "requests read" on public.requests for select to authenticated using (public.is_member());
drop policy if exists "requests insert" on public.requests;
create policy "requests insert" on public.requests for insert to authenticated with check (rider = auth.uid() and public.is_member());
drop policy if exists "requests update" on public.requests;
create policy "requests update" on public.requests for update to authenticated
  using (exists (select 1 from public.rides r where r.id = ride_id and r.driver = auth.uid()))
  with check (exists (select 1 from public.rides r where r.id = ride_id and r.driver = auth.uid()));
drop policy if exists "requests delete" on public.requests;
create policy "requests delete" on public.requests for delete to authenticated
  using (rider = auth.uid() or public.is_organizer() or exists (select 1 from public.rides r where r.id = ride_id and r.driver = auth.uid()));

-- waitlist: members see all; you add and remove your own
drop policy if exists "wanted read" on public.wanted;
create policy "wanted read" on public.wanted for select to authenticated using (public.is_member());
drop policy if exists "wanted insert" on public.wanted;
create policy "wanted insert" on public.wanted for insert to authenticated with check (rider = auth.uid() and public.is_member());
drop policy if exists "wanted delete" on public.wanted;
create policy "wanted delete" on public.wanted for delete to authenticated using (rider = auth.uid() or public.is_organizer());

-- ratings: members see all; you can only rate someone you shared a confirmed ride with
drop policy if exists "ratings read" on public.ratings;
create policy "ratings read" on public.ratings for select to authenticated using (public.is_member());
drop policy if exists "ratings insert" on public.ratings;
create policy "ratings insert" on public.ratings for insert to authenticated with check (
  rater = auth.uid() and public.is_member() and exists (
    select 1 from public.requests q where q.ride_id = ratings.ride_id and q.status = 'confirmed'
      and ((q.rider = auth.uid() and q.driver = ratings.target) or (q.driver = auth.uid() and q.rider = ratings.target))));
drop policy if exists "ratings update" on public.ratings;
create policy "ratings update" on public.ratings for update to authenticated using (rater = auth.uid()) with check (rater = auth.uid());

-- schedules: you see your own; organizers see everyone's
drop policy if exists "schedules read" on public.schedules;
create policy "schedules read" on public.schedules for select to authenticated using (user_id = auth.uid() or public.is_organizer());
drop policy if exists "schedules insert" on public.schedules;
create policy "schedules insert" on public.schedules for insert to authenticated with check (user_id = auth.uid() and public.is_member());
drop policy if exists "schedules update" on public.schedules;
create policy "schedules update" on public.schedules for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "schedules delete" on public.schedules;
create policy "schedules delete" on public.schedules for delete to authenticated using (user_id = auth.uid());

-- survey: you see your own answers; organizers see all; everyone sees the totals through survey_results()
drop policy if exists "survey read" on public.survey;
create policy "survey read" on public.survey for select to authenticated using (user_id = auth.uid() or public.is_organizer());
drop policy if exists "survey insert" on public.survey;
create policy "survey insert" on public.survey for insert to authenticated with check (user_id = auth.uid() and public.is_member());
drop policy if exists "survey update" on public.survey;
create policy "survey update" on public.survey for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "notes read" on public.survey_notes;
create policy "notes read" on public.survey_notes for select to authenticated using (user_id = auth.uid() or public.is_organizer());
drop policy if exists "notes insert" on public.survey_notes;
create policy "notes insert" on public.survey_notes for insert to authenticated with check (user_id = auth.uid() and public.is_member());
drop policy if exists "notes update" on public.survey_notes;
create policy "notes update" on public.survey_notes for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Anonymous survey totals for the public results charts (no names or ids)
drop function if exists public.survey_results();
create or replace function public.survey_results() returns table (answers jsonb)
language sql stable security definer set search_path = public as $$
  select s.answers from public.survey s;
$$;
revoke all on function public.survey_results() from public;
grant execute on function public.survey_results() to anon, authenticated;
grant execute on function public.is_organizer() to authenticated;
grant execute on function public.is_member() to authenticated;

-- ============ Profile photos ============
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
  on conflict (id) do nothing;
drop policy if exists "avatars upload own" on storage.objects;
create policy "avatars upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text and public.is_member());
drop policy if exists "avatars update own" on storage.objects;
create policy "avatars update own" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars delete own" on storage.objects;
create policy "avatars delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============ Live updates ============
do $$
declare t text;
begin
  foreach t in array array['rides', 'requests', 'wanted', 'ratings', 'profiles', 'survey'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ============ Make yourself an organizer ============
-- Replace the address below with your own (and your teammates'), then run just these lines again.
-- insert into public.organizers (email) values ('your-onyen@unc.edu') on conflict do nothing;
-- To let a non-UNC address in for testing:
-- insert into public.allowed_emails (email) values ('someone@gmail.com') on conflict do nothing;
