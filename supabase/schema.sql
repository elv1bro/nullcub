-- Ragdoll Faces — cloud progress (Supabase Postgres)
-- Выполни в SQL Editor проекта Supabase после создания проекта.
-- Auth: включи Google и Discord в Authentication → Providers.

create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'YOU',
  colors jsonb not null default '{"main":"#38bdf8","secondary":"#0284c7"}'::jsonb,
  use_camera boolean not null default false,
  use_microphone boolean not null default false,
  face_effect text not null default 'none',
  avatar_face_id text not null default 'human_default',
  last_battle_avatar_face_id text,
  last_battle_medal_id text,
  updated_at timestamptz not null default now()
);

create table if not exists public.player_stats (
  user_id uuid primary key references auth.users (id) on delete cascade,
  battles int not null default 0,
  wins int not null default 0,
  losses int not null default 0,
  loss_streak int not null default 0,
  medals jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.campaign_progress (
  user_id uuid not null references auth.users (id) on delete cascade,
  campaign_id text not null,
  max_unlocked_order int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, campaign_id)
);

alter table public.profiles enable row level security;
alter table public.player_stats enable row level security;
alter table public.campaign_progress enable row level security;

create policy "profiles_own"
  on public.profiles for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "stats_own"
  on public.player_stats for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "campaign_own"
  on public.campaign_progress for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Автосоздание пустых строк при первом логине
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'YOU')
  )
  on conflict (user_id) do nothing;

  insert into public.player_stats (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.campaign_progress (user_id, campaign_id, max_unlocked_order)
  values (new.id, 'bouncer', 0)
  on conflict (user_id, campaign_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
