-- Shadow Hunter Accountability: initial Supabase schema
-- Run in Supabase SQL Editor. This creates tables and RLS policies only;
-- the frontend Realtime/WebRTC workflows still need to be connected.

create extension if not exists pgcrypto;

create table if not exists public.hunter_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Hunter',
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(8),'hex'),1,10)),
  created_at timestamptz not null default now()
);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  unique(requester_id, addressee_id),
  check(requester_id <> addressee_id)
);

create table if not exists public.friendships (
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_a,user_b),
  check(user_a < user_b)
);

create table if not exists public.study_rooms (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  room_code text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,8)),
  title text not null default 'Focus Room',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.study_room_members (
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  presence text not null default 'focus' check(presence in ('focus','break','idle')),
  primary key(room_id,user_id)
);

create table if not exists public.accountability_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.study_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid references auth.users(id) on delete cascade,
  body text not null check(length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  check ((room_id is not null and recipient_id is null) or (room_id is null and recipient_id is not null))
);

create table if not exists public.accountability_reminders (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  message text not null default 'Time to study!' check(length(message) between 1 and 240),
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check(sender_id <> recipient_id)
);

create index if not exists friend_requests_addressee_idx on public.friend_requests(addressee_id,status);
create index if not exists messages_room_created_idx on public.accountability_messages(room_id,created_at);
create index if not exists reminders_recipient_created_idx on public.accountability_reminders(recipient_id,created_at desc);

-- Create a Hunter profile automatically for each new authenticated account.
create or replace function public.create_hunter_profile()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.hunter_profiles(user_id,display_name)
  values(new.id, coalesce(nullif(split_part(new.email,'@',1),''),'Hunter'))
  on conflict(user_id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created_hunter_profile on auth.users;
create trigger on_auth_user_created_hunter_profile
after insert on auth.users for each row execute procedure public.create_hunter_profile();

-- SECURITY DEFINER helper avoids recursive RLS when checking room membership.
create or replace function public.is_study_room_member(target_room uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.study_room_members where room_id=target_room and user_id=auth.uid());
$$;
revoke all on function public.is_study_room_member(uuid) from public;
grant execute on function public.is_study_room_member(uuid) to authenticated;

-- Accepting a request creates a canonical friendship row.
create or replace function public.create_friendship_on_accept()
returns trigger language plpgsql security definer set search_path=public as $$
declare first_user uuid; second_user uuid;
begin
  if new.status='accepted' and old.status is distinct from 'accepted' then
    first_user := least(new.requester_id,new.addressee_id);
    second_user := greatest(new.requester_id,new.addressee_id);
    insert into public.friendships(user_a,user_b) values(first_user,second_user) on conflict do nothing;
  end if;
  return new;
end; $$;
drop trigger if exists friend_request_accept_creates_friendship on public.friend_requests;
create trigger friend_request_accept_creates_friendship
after update of status on public.friend_requests for each row execute procedure public.create_friendship_on_accept();

alter table public.hunter_profiles enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.study_rooms enable row level security;
alter table public.study_room_members enable row level security;
alter table public.accountability_messages enable row level security;
alter table public.accountability_reminders enable row level security;

-- Profiles: authenticated users can read invite codes and update only their own profile.
create policy "profiles readable by authenticated" on public.hunter_profiles for select to authenticated using (true);
create policy "profile owner inserts" on public.hunter_profiles for insert to authenticated with check (auth.uid()=user_id);
create policy "profile owner updates" on public.hunter_profiles for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);

-- Friend requests: sender creates; either participant can read; recipient responds.
create policy "participants read friend requests" on public.friend_requests for select to authenticated using (auth.uid() in (requester_id,addressee_id));
create policy "sender creates friend requests" on public.friend_requests for insert to authenticated with check (auth.uid()=requester_id);
create policy "recipient responds to friend requests" on public.friend_requests for update to authenticated using (auth.uid()=addressee_id) with check (auth.uid()=addressee_id);
create policy "sender cancels friend requests" on public.friend_requests for delete to authenticated using (auth.uid()=requester_id);

-- Friendship rows are visible only to their two participants.
create policy "friends read own links" on public.friendships for select to authenticated using (auth.uid() in (user_a,user_b));

-- Room visibility and membership. Membership insertion is restricted to self;
-- joining by room code must be mediated by a validated server-side function in production.
create policy "room owner or member reads room" on public.study_rooms for select to authenticated using (owner_id=auth.uid() or public.is_study_room_member(id));
create policy "owner creates room" on public.study_rooms for insert to authenticated with check (owner_id=auth.uid());
create policy "owner updates room" on public.study_rooms for update to authenticated using (owner_id=auth.uid()) with check (owner_id=auth.uid());
create policy "members read room roster" on public.study_room_members for select to authenticated using (public.is_study_room_member(room_id));
create policy "room owner adds own membership" on public.study_room_members for insert to authenticated with check (user_id=auth.uid() and exists(select 1 from public.study_rooms r where r.id=room_id and r.owner_id=auth.uid()));
create policy "user updates own presence" on public.study_room_members for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "user leaves room" on public.study_room_members for delete to authenticated using (user_id=auth.uid());

-- Messages are readable by the sender/recipient or current room members.
create policy "message participants read" on public.accountability_messages for select to authenticated using (
 sender_id=auth.uid() or recipient_id=auth.uid() or
 (room_id is not null and public.is_study_room_member(accountability_messages.room_id))
);
create policy "send own messages" on public.accountability_messages for insert to authenticated with check (
 sender_id=auth.uid() and ((room_id is not null and recipient_id is null and public.is_study_room_member(accountability_messages.room_id)) or
 (room_id is null and recipient_id is not null and exists(select 1 from public.friendships f where (f.user_a=auth.uid() and f.user_b=recipient_id) or (f.user_b=auth.uid() and f.user_a=recipient_id))))
);

-- Reminders can be sent only to an accepted friend; recipients can mark as read.
create policy "sender or recipient reads reminders" on public.accountability_reminders for select to authenticated using (auth.uid() in (sender_id,recipient_id));
create policy "send reminder to friend" on public.accountability_reminders for insert to authenticated with check (
 sender_id=auth.uid() and exists(select 1 from public.friendships f where (f.user_a=auth.uid() and f.user_b=recipient_id) or (f.user_b=auth.uid() and f.user_a=recipient_id))
);
create policy "recipient marks reminder read" on public.accountability_reminders for update to authenticated using (recipient_id=auth.uid()) with check (recipient_id=auth.uid());

-- Realtime: enable for chat/reminders/requests after running this script.
alter publication supabase_realtime add table public.friend_requests;
alter publication supabase_realtime add table public.accountability_messages;
alter publication supabase_realtime add table public.accountability_reminders;
alter publication supabase_realtime add table public.study_room_members;
