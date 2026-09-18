-- 明记家乡小食店 ERP · 手机后台推送订阅表
-- 用法：Supabase → SQL Editor → 粘贴运行（可重复运行）。
create table if not exists public.erp_push_subs (
  endpoint    text primary key,
  sub         jsonb not null,
  email       text,
  role        text,
  updated_at  timestamptz not null default now()
);
alter table public.erp_push_subs enable row level security;
drop policy if exists "erp_push_subs authed" on public.erp_push_subs;
create policy "erp_push_subs authed"
  on public.erp_push_subs for all
  to authenticated using (true) with check (true);
-- ⚠️ 正式上线前记得跑 security-hardening.sql，会把这条收紧成只有白名单里的人能读写。
