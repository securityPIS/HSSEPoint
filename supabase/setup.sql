-- =========================================================
-- HSSE POINT — Setup Supabase (Auth Google + Role + Cloud Data)
-- Jalankan SELURUH skrip ini di: Supabase Dashboard > SQL Editor > New query.
-- Aman dijalankan berulang (idempotent).
-- =========================================================

-- 1) PROFIL PENGGUNA -------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  full_name  text,
  phone      text,
  division   text,
  role       text check (role in ('user','management','admin')),
  status     text not null default 'new' check (status in ('new','pending','active','rejected')),
  created_at timestamptz not null default now()
);

-- 2) PERUSAHAAN ------------------------------------------------------------
create table if not exists public.companies (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  created_at timestamptz not null default now()
);

-- 3) RELASI USER <-> PERUSAHAAN (many-to-many) ----------------------------
create table if not exists public.user_companies (
  user_id    uuid references public.profiles(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  primary key (user_id, company_id)
);

-- 4) LOKASI (denah + titik perangkat, per perusahaan) ---------------------
create table if not exists public.locations (
  id           text primary key,
  company_id   uuid references public.companies(id) on delete cascade,
  company_name text,
  data         jsonb not null default '{}'::jsonb,
  created_by   uuid default auth.uid(),
  updated_by   uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- 5) HELPER (SECURITY DEFINER -> bypass RLS saat cek role, hindari rekursi)
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin' and p.status = 'active');
$$;

create or replace function public.can_write()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.status = 'active' and p.role in ('user','admin'));
$$;

create or replace function public.is_member(cid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.user_companies uc
                 where uc.user_id = auth.uid() and uc.company_id = cid);
$$;

-- 6) TRIGGER: buat profil otomatis saat user Google baru mendaftar ---------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, status)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
          'new')
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 7) RPC: user minta akses (isi data diri + status 'pending') --------------
--    Aman: user TIDAK bisa mengubah role-nya sendiri lewat fungsi ini.
create or replace function public.request_access(p_full_name text, p_phone text, p_division text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
     set full_name = p_full_name,
         phone     = p_phone,
         division  = p_division,
         status    = 'pending'
   where id = auth.uid()
     and status in ('new','pending','rejected');  -- user yang sudah aktif tidak terpengaruh
end; $$;

-- 8) updated_at otomatis pada locations -----------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); new.updated_by = auth.uid(); return new; end; $$;

drop trigger if exists locations_touch on public.locations;
create trigger locations_touch before update on public.locations
  for each row execute function public.touch_updated_at();

-- 9) AKTIFKAN ROW LEVEL SECURITY ------------------------------------------
alter table public.profiles       enable row level security;
alter table public.companies      enable row level security;
alter table public.user_companies enable row level security;
alter table public.locations      enable row level security;

-- 10) POLICIES -------------------------------------------------------------
-- profiles: user lihat/insert dirinya (status 'new'); hanya admin yang meng-update.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or public.is_admin());

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles for insert
  with check (id = auth.uid() and role is null and status = 'new');

drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles for update
  using (public.is_admin()) with check (public.is_admin());

-- companies: semua user login boleh baca; hanya admin yang mengubah.
drop policy if exists companies_select on public.companies;
create policy companies_select on public.companies for select
  using (auth.uid() is not null);

drop policy if exists companies_admin_all on public.companies;
create policy companies_admin_all on public.companies for all
  using (public.is_admin()) with check (public.is_admin());

-- user_companies: user lihat miliknya; hanya admin yang mengatur.
drop policy if exists uc_select on public.user_companies;
create policy uc_select on public.user_companies for select
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists uc_admin_all on public.user_companies;
create policy uc_admin_all on public.user_companies for all
  using (public.is_admin()) with check (public.is_admin());

-- locations: baca sesuai keanggotaan perusahaan; tulis untuk role user/admin.
drop policy if exists loc_select on public.locations;
create policy loc_select on public.locations for select
  using (public.is_admin() or public.is_member(company_id));

drop policy if exists loc_insert on public.locations;
create policy loc_insert on public.locations for insert
  with check (public.is_admin() or (public.can_write() and public.is_member(company_id)));

drop policy if exists loc_update on public.locations;
create policy loc_update on public.locations for update
  using      (public.is_admin() or (public.can_write() and public.is_member(company_id)))
  with check (public.is_admin() or (public.can_write() and public.is_member(company_id)));

drop policy if exists loc_delete on public.locations;
create policy loc_delete on public.locations for delete
  using (public.is_admin() or (public.can_write() and public.is_member(company_id)));

-- 11) HARDENING HAK AKSES FUNGSI ------------------------------------------
-- Supabase secara default memberi EXECUTE ke anon/authenticated pada setiap
-- fungsi baru di schema public. Fungsi SECURITY DEFINER sebaiknya TIDAK bisa
-- dipanggil anon sebagai RPC. Cabut dari anon; sisakan authenticated hanya
-- untuk yang dibutuhkan (helper dipakai RLS + request_access).
revoke execute on function public.is_admin()                       from anon;
revoke execute on function public.can_write()                      from anon;
revoke execute on function public.is_member(uuid)                  from anon;
revoke execute on function public.request_access(text, text, text) from anon;
-- Fungsi trigger tidak untuk dipanggil siapa pun (jalan sebagai definer via trigger).
revoke execute on function public.handle_new_user()  from public, anon, authenticated;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

grant execute on function public.is_admin()                       to authenticated;
grant execute on function public.can_write()                      to authenticated;
grant execute on function public.is_member(uuid)                  to authenticated;
grant execute on function public.request_access(text, text, text) to authenticated;

-- 12) ADMIN PERTAMA --------------------------------------------------------
-- Login DULU sekali via Google di aplikasi supaya baris profil Anda terbuat,
-- lalu jalankan perintah ini (ganti dengan email Google Anda):
--
--   update public.profiles set role = 'admin', status = 'active'
--   where email = 'EMAIL-ANDA@gmail.com';
--
-- Setelah itu buka menu "Kelola User" di aplikasi untuk menyetujui user lain,
-- menetapkan role, dan menugaskan perusahaan.
