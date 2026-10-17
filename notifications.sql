-- ============================================================
-- سجادتك: إشعار على جوالك عند كل طلب جديد (شغّله مرة واحدة في Supabase > SQL Editor)
-- يعمل مع تطبيق ntfy المجاني (iPhone وAndroid). الإشعار فيه الاسم والمنطقة والمبلغ فقط، بدون رقم الهاتف أو العنوان.
-- ============================================================
create extension if not exists pg_net with schema extensions;

-- جدول أسرار مغلق تماماً (لا أحد يصل إليه من الموقع)
create table if not exists public.app_secrets (k text primary key, v text not null);
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;

-- رمز قناة إشعارات سرّي وطويل يُولَّد تلقائياً (لا تشاركه مع أحد)
insert into public.app_secrets (k, v)
values ('ntfy_topic', 'sejadtak-' || substr(md5(random()::text || clock_timestamp()::text || gen_random_uuid()::text), 1, 20))
on conflict (k) do nothing;

create or replace function public.notify_new_order()
returns trigger language plpgsql security definer set search_path = public, extensions, net as $$
declare t text; msg text;
begin
  select v into t from public.app_secrets where k = 'ntfy_topic';
  if t is null or t = '' then return new; end if;
  msg := new.name || E'\n' || coalesce(new.area, '') ||
         case when new.mode = 'custom' then E'\nتصميم خاص' else E'\n' || new.total || ' د.أ' end ||
         case when new.img <> '' then E'\nمعه صورة' else '' end;
  begin
    perform net.http_post(
      url := 'https://ntfy.sh',
      body := jsonb_build_object('topic', t, 'title', 'طلب جديد من سجادتك', 'message', msg, 'priority', 4,
                                  'tags', jsonb_build_array('bell'), 'click', 'https://sejadtak.shop/admin'),
      headers := '{"Content-Type":"application/json"}'::jsonb);
  exception when others then null;   -- أي خطأ بالإشعار لا يمنع حفظ الطلب أبداً
  end;
  return new;
end $$;
revoke all on function public.notify_new_order() from public, anon, authenticated;

drop trigger if exists orders_notify on public.orders;
create trigger orders_notify after insert on public.orders
  for each row execute function public.notify_new_order();

-- إشعار عند وصول رأي جديد من زبون
create or replace function public.notify_new_review()
returns trigger language plpgsql security definer set search_path = public, extensions, net as $$
declare t text;
begin
  if not new.pending then return new; end if;
  select v into t from public.app_secrets where k = 'ntfy_topic';
  if t is null or t = '' then return new; end if;
  begin
    perform net.http_post(
      url := 'https://ntfy.sh',
      body := jsonb_build_object('topic', t, 'title', 'رأي جديد بانتظار موافقتك', 'message', new.name || E'\n' || left(new.body, 120), 'priority', 3,
                                  'tags', jsonb_build_array('speech_balloon'), 'click', 'https://sejadtak.shop/admin'),
      headers := '{"Content-Type":"application/json"}'::jsonb);
  exception when others then null;
  end;
  return new;
end $$;
revoke all on function public.notify_new_review() from public, anon, authenticated;
drop trigger if exists reviews_notify on public.reviews;
create trigger reviews_notify after insert on public.reviews
  for each row execute function public.notify_new_review();

-- آخر سطر يعرض لك رمز القناة: انسخه واكتبه في تطبيق ntfy (Subscribe to topic)
select v as "رمز الإشعارات" from public.app_secrets where k = 'ntfy_topic';
