-- ============================================================
-- سجادتك: قاعدة البيانات والحماية (شغّله مرة واحدة في Supabase > SQL Editor)
-- الحماية الحقيقية هنا (Row Level Security): الزوار يقرؤون فقط،
-- والكتابة والتعديل والحذف لحساب الأدمن وحده.
-- ============================================================

-- 1) الأدمن
create table if not exists public.admins (
  uid uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;   -- بدون أي سياسة = لا أحد يصل إليه من الموقع

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where uid = auth.uid());
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- 2) الجداول
create table if not exists public.site_texts (
  key text primary key check (char_length(key) <= 80),
  value text not null check (char_length(value) <= 2000),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  cat text not null check (cat in ('kb','car','wall','floor')),
  name text not null check (char_length(name) between 1 and 120),
  disc int not null default 0 check (disc between 0 and 90),
  sizes jsonb not null default '[]' check (jsonb_typeof(sizes) = 'array' and jsonb_array_length(sizes) <= 12),
  imgs jsonb not null default '[]' check (jsonb_typeof(imgs) = 'array' and jsonb_array_length(imgs) <= 12),
  active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.offers (
  id uuid primary key default gen_random_uuid(),
  kicker text not null default '' check (char_length(kicker) <= 80),
  title text not null default '' check (char_length(title) <= 120),
  badge text not null default '' check (char_length(badge) <= 40),
  body text not null default '' check (char_length(body) <= 600),
  cta text not null default '' check (char_length(cta) <= 60),
  act text not null default '' check (act in ('','browse','custom')),
  img text not null default '' check (char_length(img) <= 600),
  active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  img text not null check (char_length(img) <= 600),
  name text not null default '' check (char_length(name) <= 80),
  stars int not null default 5 check (stars between 1 and 5),
  active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null check (char_length(name) between 1 and 120),
  phone text not null check (char_length(phone) between 6 and 30),
  area text not null default '' check (char_length(area) <= 120),
  address text not null default '' check (char_length(address) <= 400),
  mode text not null default 'single' check (mode in ('single','cart','custom')),
  items jsonb not null default '[]' check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) <= 40),
  total numeric not null default 0 check (total >= 0 and total < 1000000),
  days int not null default 0 check (days between 0 and 365),
  img text not null default '' check (img = '' or img ~ '^[a-z0-9]{6,40}\.jpg$'),
  status text not null default 'new' check (status in ('new','approved','doing','done','cancel'))
);

-- للمشاريع التي أنشأت الجدول سابقاً: يضيف عمود الصورة وحالة "مقبول"
alter table public.orders add column if not exists img text not null default '' check (img = '' or img ~ '^[a-z0-9]{6,40}\.jpg$');
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check (status in ('new','approved','doing','done','cancel'));

-- 3) الحماية (RLS)
alter table public.site_texts enable row level security;
alter table public.products   enable row level security;
alter table public.offers     enable row level security;
alter table public.reviews    enable row level security;
alter table public.orders     enable row level security;

-- قراءة عامة لمحتوى المتجر المفعّل فقط
drop policy if exists "read texts"   on public.site_texts;
drop policy if exists "read products" on public.products;
drop policy if exists "read offers"  on public.offers;
drop policy if exists "read reviews" on public.reviews;
create policy "read texts"    on public.site_texts for select using (true);
create policy "read products" on public.products   for select using (active or public.is_admin());
create policy "read offers"   on public.offers     for select using (active or public.is_admin());
create policy "read reviews"  on public.reviews    for select using (active or public.is_admin());

-- كتابة كاملة للأدمن فقط
drop policy if exists "admin texts"   on public.site_texts;
drop policy if exists "admin products" on public.products;
drop policy if exists "admin offers"  on public.offers;
drop policy if exists "admin reviews" on public.reviews;
create policy "admin texts"    on public.site_texts for all using (public.is_admin()) with check (public.is_admin());
create policy "admin products" on public.products   for all using (public.is_admin()) with check (public.is_admin());
create policy "admin offers"   on public.offers     for all using (public.is_admin()) with check (public.is_admin());
create policy "admin reviews"  on public.reviews    for all using (public.is_admin()) with check (public.is_admin());

-- الطلبات: الزائر يضيف طلباً فقط (لا يقرأ ولا يعدّل)، والأدمن يرى ويدير
drop policy if exists "visitor insert orders" on public.orders;
drop policy if exists "admin orders" on public.orders;
create policy "visitor insert orders" on public.orders for insert to anon, authenticated with check (status = 'new');
create policy "admin orders" on public.orders for all using (public.is_admin()) with check (public.is_admin());

-- 4) تخزين الصور (حاوية عامة للقراءة، الرفع والحذف للأدمن فقط)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('images', 'images', true, 5242880, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/png','image/jpeg','image/webp'];

drop policy if exists "images read"  on storage.objects;
drop policy if exists "images admin" on storage.objects;
create policy "images read"  on storage.objects for select using (bucket_id = 'images');
create policy "images admin" on storage.objects for all
  using (bucket_id = 'images' and public.is_admin())
  with check (bucket_id = 'images' and public.is_admin());

-- 4ب) صور طلبات الزبائن: حاوية خاصة. الزائر يرفع فقط (jpg حتى ٣ ميغا) ولا يقرأ ولا يحذف، والأدمن وحده يرى وينزّل ويحذف
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('order-images', 'order-images', false, 3145728, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 3145728, allowed_mime_types = array['image/jpeg'];

drop policy if exists "order img insert" on storage.objects;
drop policy if exists "order img admin" on storage.objects;
create policy "order img insert" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'order-images' and name ~ '^[a-z0-9]{6,40}\.jpg$');
create policy "order img admin" on storage.objects for all
  using (bucket_id = 'order-images' and public.is_admin())
  with check (bucket_id = 'order-images' and public.is_admin());

-- 4ج) الإحصائيات: الزائر يضيف أحداثاً مجهولة فقط (زيارة، مشاهدة قطعة، إضافة للسلة، مدة بقاء)، والأدمن وحده يقرأها
create table if not exists public.events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  type text not null check (type in ('visit','product','cart','time')),
  sid text not null check (sid ~ '^[a-z0-9]{6,32}$'),
  vid text not null check (vid ~ '^[a-z0-9]{6,32}$'),
  pid text not null default '' check (char_length(pid) <= 64),
  label text not null default '' check (char_length(label) <= 120),
  secs int not null default 0 check (secs between 0 and 14400)
);
create index if not exists events_type_time on public.events (type, created_at);
create index if not exists events_sid on public.events (sid);
alter table public.events enable row level security;
grant insert on public.events to anon, authenticated;
drop policy if exists "visitor insert events" on public.events;
drop policy if exists "admin events" on public.events;
create policy "visitor insert events" on public.events for insert to anon, authenticated with check (true);
create policy "admin events" on public.events for all using (public.is_admin()) with check (public.is_admin());

-- ملخص الإحصائيات (للأدمن فقط): days = عدد الأيام الأخيرة، و0 = كل الفترة
create or replace function public.admin_stats(days int default 7)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare since timestamptz; r jsonb;
begin
  if not public.is_admin() then raise exception 'denied'; end if;
  since := case when days > 0 then now() - make_interval(days => days) else '-infinity'::timestamptz end;
  select jsonb_build_object(
    'visitors', (select count(distinct vid) from events where type = 'visit' and created_at >= since),
    'sessions', (select count(distinct sid) from events where type = 'visit' and created_at >= since),
    'product_views', (select count(*) from events where type = 'product' and created_at >= since),
    'cart_adds', (select count(*) from events where type = 'cart' and created_at >= since),
    'avg_secs', (select coalesce(round(avg(m)), 0) from (select max(secs) m from events where type = 'time' and created_at >= since group by sid) x),
    'max_secs', (select coalesce(max(m), 0) from (select max(secs) m from events where type = 'time' and created_at >= since group by sid) x),
    'timed_sessions', (select count(*) from (select 1 from events where type = 'time' and created_at >= since group by sid) x),
    'products', coalesce((select jsonb_agg(p order by p.views desc, p.carts desc) from (
        select pid, max(label) as name, count(*) filter (where type = 'product') as views,
               count(distinct vid) filter (where type = 'product') as uniq, count(*) filter (where type = 'cart') as carts
        from events where type in ('product','cart') and pid <> '' and created_at >= since
        group by pid order by 3 desc, 5 desc limit 60) p), '[]'::jsonb),
    'hours', coalesce((select jsonb_agg(jsonb_build_object('h', h, 'n', n) order by h) from (
        select extract(hour from created_at at time zone 'Asia/Amman')::int as h, count(*) as n
        from events where type = 'visit' and created_at >= since group by 1) q), '[]'::jsonb),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('d', d, 'n', n, 'u', u) order by d) from (
        select (created_at at time zone 'Asia/Amman')::date as d, count(*) as n, count(distinct vid) as u
        from events where type = 'visit' and created_at >= greatest(since, now() - interval '60 days') group by 1) q), '[]'::jsonb)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_stats(int) from public, anon;
grant execute on function public.admin_stats(int) to authenticated;

-- 4د) آراء الزبائن: الزائر يرسل رأياً "بانتظار الموافقة" فقط، ولا يظهر بالموقع حتى توافق عليه من الأدمن
alter table public.reviews add column if not exists body text not null default '' check (char_length(body) <= 400);
alter table public.reviews add column if not exists pending boolean not null default false;
alter table public.reviews alter column img set default '';
drop policy if exists "visitor insert reviews" on public.reviews;
create policy "visitor insert reviews" on public.reviews for insert to anon, authenticated
  with check (active = false and pending = true and char_length(name) between 1 and 80 and char_length(body) between 1 and 400
              and (img = '' or img ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/images/reviews/[a-z0-9]{6,40}\.jpg$'));
-- رفع صور الآراء (jpg فقط، داخل مجلد reviews)
drop policy if exists "review img insert" on storage.objects;
create policy "review img insert" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'images' and name ~ '^reviews/[a-z0-9]{6,40}\.jpg$');

-- 5) إشعار فوري بالطلبات الجديدة داخل لوحة الأدمن
do $$ begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then null; end $$;

-- 6) آخر خطوة: اجعل حسابك أنت الأدمن.
--    أنشئ المستخدم أولاً من Authentication > Users > Add user (بريد وكلمة سر قوية)،
--    ثم بدّل البريد أدناه ببريدك وشغّل هذا السطر وحده (البريد يبقى هنا فقط ولا يدخل أي كود للموقع):
-- insert into public.admins (uid) select id from auth.users where email = 'ضع-بريدك-هنا@example.com';
