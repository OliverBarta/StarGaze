-- StarGaze: profiles, follows, captures. Auth comes from Auth0 via Supabase Third-Party Auth,
-- so user IDs are Auth0 `sub` strings, not auth.users UUIDs.

-- The Auth0 user ID of the caller, or null when unauthenticated.
create or replace function public.requesting_user_id()
returns text
language sql stable
as $$
  select nullif(auth.jwt() ->> 'sub', '')
$$;

-- ── Profiles ────────────────────────────────────────────────────────────────
create table public.profiles (
  id           text primary key default public.requesting_user_id(),
  username     text not null unique
               check (username ~ '^[a-z0-9_]{3,20}$'),   -- lowercase only, so unique is case-insensitive
  display_name text check (char_length(display_name) <= 50),
  avatar_url   text,
  created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Any signed-in user can look people up (needed to follow by username).
create policy "Profiles are readable by signed-in users"
  on public.profiles for select to authenticated
  using (true);

create policy "Users create their own profile"
  on public.profiles for insert to authenticated
  with check (id = (select public.requesting_user_id()));

create policy "Users update their own profile"
  on public.profiles for update to authenticated
  using (id = (select public.requesting_user_id()))
  with check (id = (select public.requesting_user_id()));

create policy "Users delete their own profile"
  on public.profiles for delete to authenticated
  using (id = (select public.requesting_user_id()));

-- ── Follows ─────────────────────────────────────────────────────────────────
create table public.follows (
  follower_id text not null default public.requesting_user_id()
              references public.profiles (id) on delete cascade,
  followee_id text not null
              references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);

create index follows_followee_idx on public.follows (followee_id);

alter table public.follows enable row level security;

-- You can see who you follow and who follows you.
create policy "See follows involving me"
  on public.follows for select to authenticated
  using ((select public.requesting_user_id()) in (follower_id, followee_id));

create policy "Follow as myself"
  on public.follows for insert to authenticated
  with check (follower_id = (select public.requesting_user_id()));

create policy "Unfollow as myself"
  on public.follows for delete to authenticated
  using (follower_id = (select public.requesting_user_id()));

-- ── Captures (discoveries) ──────────────────────────────────────────────────
-- Repeat scans of the same constellation are allowed; FriendStanding.ranked dedupes per week.
-- The app re-uploads all local discoveries on launch, so (user, constellation, time) is unique
-- and uploads use `on conflict do nothing`.
create table public.captures (
  id                 uuid primary key default gen_random_uuid(),
  user_id            text not null default public.requesting_user_id()
                     references public.profiles (id) on delete cascade,
  constellation_name text not null,
  location_name      text not null default '',
  captured_at        timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  unique (user_id, constellation_name, captured_at)
);

create index captures_user_time_idx on public.captures (user_id, captured_at desc);

alter table public.captures enable row level security;

create policy "Read my captures and those of people I follow"
  on public.captures for select to authenticated
  using (
    user_id = (select public.requesting_user_id())
    or exists (
      select 1 from public.follows f
      where f.follower_id = (select public.requesting_user_id())
        and f.followee_id = captures.user_id
    )
  );

create policy "Add my own captures"
  on public.captures for insert to authenticated
  with check (user_id = (select public.requesting_user_id()));

create policy "Delete my own captures"
  on public.captures for delete to authenticated
  using (user_id = (select public.requesting_user_id()));

-- ── Feed ────────────────────────────────────────────────────────────────────
-- Followed users' captures with their profile, newest first. security_invoker makes the
-- view run under the caller's RLS, so it only ever returns people the caller follows.
create view public.feed
with (security_invoker = true) as
select
  c.id,
  c.constellation_name,
  c.location_name,
  c.captured_at,
  p.id           as user_id,
  p.username,
  p.display_name,
  p.avatar_url
from public.captures c
join public.profiles p on p.id = c.user_id
where c.user_id <> public.requesting_user_id()
order by c.captured_at desc;

-- ── Privileges ──────────────────────────────────────────────────────────────
-- New Supabase projects don't expose tables to the API roles automatically.
-- Only signed-in users get access; RLS above limits them to the right rows.
grant usage on schema public to authenticated;
grant execute on function public.requesting_user_id() to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, delete on public.follows to authenticated;
grant select, insert, delete on public.captures to authenticated;
grant select on public.feed to authenticated;

-- ── Light readings ──────────────────────────────────────────────────────────
-- A strength value at a point. Postgres has no tuple type, so coordinates use the
-- built-in `point` (x, y); PostgREST sends it as the string "(x,y)".
create table public.light_readings (
  id          bigint generated always as identity primary key,
  coordinates point not null,
  strength    double precision not null
);

alter table public.light_readings enable row level security;

create policy "Light readings are readable by anyone"
  on public.light_readings for select to anon, authenticated
  using (true);

create policy "Signed-in users add light readings"
  on public.light_readings for insert to authenticated
  with check (true);

create policy "Signed-in users update light readings"
  on public.light_readings for update to authenticated
  using (true)
  with check (true);

create policy "Signed-in users delete light readings"
  on public.light_readings for delete to authenticated
  using (true);

grant usage on schema public to anon;
grant select on public.light_readings to anon;
grant select, insert, update, delete on public.light_readings to authenticated;
