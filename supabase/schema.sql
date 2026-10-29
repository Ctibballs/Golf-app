-- Fairway online play: matches and tournaments on a free Supabase project.
--
-- Setup:
--   1. Create a project at https://supabase.com (the free tier is plenty).
--   2. Authentication → Sign In / Providers → turn on "Allow anonymous sign-ins".
--   3. SQL Editor → paste and run this file.
--   4. Project Settings → API: copy the project ref and the "anon public" key into
--      the app (Settings → Online Play) or into Fairway/App/OnlineConfig.swift.
--
-- Each device signs in anonymously. A match row is owned by its host; each participant
-- row is owned by the device that keeps that card (yours, or guests you score for).
-- Row-level security means nobody can edit anyone else's card. Rows store the app's
-- JSON models in `payload`, so the schema doesn't need to change as the app grows.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.matches (
  id            uuid primary key,
  code          text not null,
  host_user     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  status        text not null default 'lobby' check (status in ('lobby', 'live', 'finished')),
  tournament_id uuid,
  payload       jsonb not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Join codes only need to be unique among games that are still running.
create unique index if not exists matches_active_code
  on public.matches (code) where status <> 'finished';

create table if not exists public.participants (
  match_id       uuid not null references public.matches (id) on delete cascade,
  participant_id uuid not null,
  owner          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  payload        jsonb not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (match_id, participant_id)
);

create table if not exists public.tournaments (
  id         uuid primary key,
  code       text not null,
  host_user  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  status     text not null default 'registration' check (status in ('registration', 'inProgress', 'finished')),
  payload    jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists tournaments_active_code
  on public.tournaments (code) where status <> 'finished';

create table if not exists public.tournament_entrants (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  entrant_id    uuid not null,
  owner         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  payload       jsonb not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (tournament_id, entrant_id)
);

create index if not exists matches_tournament on public.matches (tournament_id);

-- ---------------------------------------------------------------------------
-- updated_at bookkeeping
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists matches_touch on public.matches;
create trigger matches_touch before update on public.matches
  for each row execute function public.touch_updated_at();

drop trigger if exists participants_touch on public.participants;
create trigger participants_touch before update on public.participants
  for each row execute function public.touch_updated_at();

drop trigger if exists tournaments_touch on public.tournaments;
create trigger tournaments_touch before update on public.tournaments
  for each row execute function public.touch_updated_at();

drop trigger if exists entrants_touch on public.tournament_entrants;
create trigger entrants_touch before update on public.tournament_entrants
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.matches enable row level security;
alter table public.participants enable row level security;
alter table public.tournaments enable row level security;
alter table public.tournament_entrants enable row level security;

-- Matches: anyone signed in can read (joining is by code); only the host changes them.
drop policy if exists "matches readable" on public.matches;
create policy "matches readable" on public.matches
  for select to authenticated using (true);

drop policy if exists "host creates match" on public.matches;
create policy "host creates match" on public.matches
  for insert to authenticated with check (host_user = (select auth.uid()));

drop policy if exists "host updates match" on public.matches;
create policy "host updates match" on public.matches
  for update to authenticated
  using (host_user = (select auth.uid()))
  with check (host_user = (select auth.uid()));

drop policy if exists "host deletes match" on public.matches;
create policy "host deletes match" on public.matches
  for delete to authenticated using (host_user = (select auth.uid()));

-- Participants: readable by everyone in the game; each card edited only by its owner.
drop policy if exists "participants readable" on public.participants;
create policy "participants readable" on public.participants
  for select to authenticated using (true);

drop policy if exists "owner adds participant" on public.participants;
create policy "owner adds participant" on public.participants
  for insert to authenticated with check (owner = (select auth.uid()));

drop policy if exists "owner updates participant" on public.participants;
create policy "owner updates participant" on public.participants
  for update to authenticated
  using (owner = (select auth.uid()))
  with check (owner = (select auth.uid()));

drop policy if exists "owner or host removes participant" on public.participants;
create policy "owner or host removes participant" on public.participants
  for delete to authenticated using (
    owner = (select auth.uid())
    or exists (select 1 from public.matches m where m.id = match_id and m.host_user = (select auth.uid()))
  );

-- Tournaments mirror matches.
drop policy if exists "tournaments readable" on public.tournaments;
create policy "tournaments readable" on public.tournaments
  for select to authenticated using (true);

drop policy if exists "host creates tournament" on public.tournaments;
create policy "host creates tournament" on public.tournaments
  for insert to authenticated with check (host_user = (select auth.uid()));

drop policy if exists "host updates tournament" on public.tournaments;
create policy "host updates tournament" on public.tournaments
  for update to authenticated
  using (host_user = (select auth.uid()))
  with check (host_user = (select auth.uid()));

drop policy if exists "host deletes tournament" on public.tournaments;
create policy "host deletes tournament" on public.tournaments
  for delete to authenticated using (host_user = (select auth.uid()));

drop policy if exists "entrants readable" on public.tournament_entrants;
create policy "entrants readable" on public.tournament_entrants
  for select to authenticated using (true);

drop policy if exists "owner enters tournament" on public.tournament_entrants;
create policy "owner enters tournament" on public.tournament_entrants
  for insert to authenticated with check (owner = (select auth.uid()));

drop policy if exists "owner updates entry" on public.tournament_entrants;
create policy "owner updates entry" on public.tournament_entrants
  for update to authenticated
  using (owner = (select auth.uid()))
  with check (owner = (select auth.uid()));

drop policy if exists "owner or host removes entry" on public.tournament_entrants;
create policy "owner or host removes entry" on public.tournament_entrants
  for delete to authenticated using (
    owner = (select auth.uid())
    or exists (select 1 from public.tournaments t where t.id = tournament_id and t.host_user = (select auth.uid()))
  );

-- ---------------------------------------------------------------------------
-- Optional housekeeping: clear out old games (requires the pg_cron extension).
-- ---------------------------------------------------------------------------
-- select cron.schedule('fairway-cleanup', '0 4 * * *', $$
--   delete from public.matches where updated_at < now() - interval '60 days';
--   delete from public.tournaments where updated_at < now() - interval '120 days';
-- $$);
