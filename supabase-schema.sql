-- ============================================================
-- 明记餐饮 ERP · Supabase 建表脚本
-- 用法：Supabase 控制台 → SQL Editor → New query → 粘贴全部 → Run
-- 已经跑过第 1 版的，只需再跑「第 2 部分」即可（重复运行安全）。
-- ============================================================

-- ========== 第 1 部分：业务数据表 erp_store ==========
create table if not exists public.erp_store (
  key         text primary key,
  value       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
alter table public.erp_store enable row level security;

-- 收紧：仅「已登录」用户可读写业务数据（未登录看不到任何东西）
drop policy if exists "erp_store anon full access" on public.erp_store;      -- 移除旧的匿名策略
drop policy if exists "erp_store authed full access" on public.erp_store;
create policy "erp_store authed full access"
  on public.erp_store for all
  to authenticated
  using (true) with check (true);

-- ========== 第 2 部分：白名单 / 用户目录 erp_users ==========
-- 只有列在此表且 active=true 的邮箱能进入系统；岗位/分店由管理员分配。
create table if not exists public.erp_users (
  email       text primary key,
  name        text,
  role        text not null default 'staff',   -- owner / area / manager / headchef / staff
  outlet      text default 'b1',               -- 所属分店 id：ck / b1 ... b11
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
alter table public.erp_users enable row level security;

-- ⚠️ 下面这两条只是「能跑起来」的最低配置，真正要用于正式营运前，
-- 务必接着跑一次同目录下的 security-hardening.sql ——那份才是把权限
-- 收紧到「只有白名单里的人能读写、只有老板/区域副经理能管人」的正式版本。
-- 这里先给宽松版本是方便你第一次建表、第一次注册老板账号时不被卡住。
drop policy if exists "erp_users authed read" on public.erp_users;
drop policy if exists "erp_users authed write" on public.erp_users;
create policy "erp_users authed read"
  on public.erp_users for select
  to authenticated using (true);
create policy "erp_users authed write"
  on public.erp_users for all
  to authenticated using (true) with check (true);

-- ============================================================
-- 首次使用：
-- 1) 上面跑完后，去 Authentication → Providers → Email 确认已开启；
--    并把「Confirm email」打开（启用）——注册要先验证邮箱才能登录，
--    避免有人用假邮箱乱注册。正式上线前这项务必是打开的。
-- 2) 打开网站 → 用你的邮箱点「注册账号」。因为白名单此刻为空，
--    第一位注册者会被自动设为『老板』。之后就能在
--    设置 → 白名单/用户管理 里添加其他员工并分配岗位/分店。
--    （也可以不靠自动引导，直接在这里手动插入第一位老板：）
-- insert into public.erp_users (email,name,role,outlet,active)
--   values ('you@example.com','老板','owner','b1',true)
--   on conflict (email) do update set role=excluded.role, active=true;
-- 3) 老板账号建好、能正常登录之后，务必跑 security-hardening.sql 收紧权限，
--    再让其他员工用真实资料注册。
-- ============================================================
