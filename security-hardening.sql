-- ============================================================
-- 明记餐饮 ERP · 权限加固补丁（正式上线前必跑）
-- 用法：Supabase 控制台 → SQL Editor → New query → 粘贴全部 → Run
-- 可重复运行，不会重复建表/重复出错。
--
-- 解决的问题：
-- 之前的规则是「只要是登录过的账号，不管有没有在白名单里、
-- 是什么职位，都能直接读写所有数据」——邀请码/白名单其实只在
-- 网页前端检查，绕过网页直接呼叫 Supabase API 就能绕过。
-- 这份补丁把权限判断搬到数据库这一层，就算绕过网页也挡得住。
-- ============================================================

-- ========== 第 1 部分：邀请码（存在数据库私有表里，不写进代码/仓库）==========
-- 邀请码 → {职位,分店} 的对照放在 erp_invite_codes 表里：
--   * 表开了 RLS 且没有任何策略，并收回 anon/authenticated 权限 → 网页/任何登录账号都读不到整张表；
--   * 只能通过下面的 security definer 函数「拿码问答案」(invite_info / invite_role / invite_outlet)；
--   * 具体的码由业主在 Supabase SQL Editor 手动 insert，**绝不提交到公开仓库**。
-- 换码：delete + insert 这张表即可，不用改网页代码。
create table if not exists public.erp_invite_codes (
  code   text primary key,          -- 一律小写
  role   text not null,
  outlet text not null
);
alter table public.erp_invite_codes enable row level security;
revoke all on public.erp_invite_codes from anon, authenticated;

create or replace function public.invite_role(code text)
returns text
language plpgsql
stable
security definer set search_path = public
as $$
declare r text;
begin
  select c.role into r from public.erp_invite_codes c
   where c.code = lower(coalesce(invite_role.code,''));
  return r;
end;
$$;

create or replace function public.invite_outlet(code text)
returns text
language plpgsql
stable
security definer set search_path = public
as $$
declare o text;
begin
  select c.outlet into o from public.erp_invite_codes c
   where c.code = lower(coalesce(invite_outlet.code,''));
  return o;
end;
$$;

-- 给网页注册时用：拿邀请码换 {role,outlet}，码不对回 null
create or replace function public.invite_info(code text)
returns json
language plpgsql
stable
security definer set search_path = public
as $$
declare r json;
begin
  select json_build_object('role', c.role, 'outlet', c.outlet) into r
    from public.erp_invite_codes c
   where c.code = lower(coalesce(invite_info.code,''));
  return r;
end;
$$;
grant execute on function public.invite_info(text) to anon, authenticated;

-- ========== 第 2 部分：判断「当前登录的人是谁 / 是不是白名单里的管理员」==========
-- security definer：以建表者(postgres)的身份运行，能绕开下面 erp_users 自己的
-- RLS 规则去查表，避免「查权限」跟「权限规则」互相卡死(无限递归)。
create or replace function public.my_email()
returns text
language sql stable
as $$ select lower(coalesce(auth.jwt()->>'email','')) $$;

create or replace function public.is_whitelisted()
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists(select 1 from public.erp_users where email = public.my_email() and active = true);
$$;

create or replace function public.is_admin()
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists(
    select 1 from public.erp_users
    where email = public.my_email() and active = true and role in ('owner','area','hrmgr')
  );
$$;

-- ========== 第 3 部分：erp_users 白名单表 —— 重新收紧 ==========
drop policy if exists "erp_users authed read" on public.erp_users;
drop policy if exists "erp_users authed write" on public.erp_users;
drop policy if exists "erp_users select self or admin" on public.erp_users;
drop policy if exists "erp_users insert self via invite or admin" on public.erp_users;
drop policy if exists "erp_users update admin only" on public.erp_users;
drop policy if exists "erp_users delete admin only" on public.erp_users;

-- 读：自己一定能读到自己那一行(登录要用)；老板/区域副经理能读全部(管理面板要用)。
create policy "erp_users select self or admin"
  on public.erp_users for select
  to authenticated
  using (is_admin() or email = my_email());

-- 新增：只允许四种情况——
--   a) 白名单整表还是空的 → 第一位注册的人自动变老板(仅限一次)
--   b) 用注册时夹带的邀请码(存在 Supabase 签发、无法伪造的 JWT 里)对应到的职位
--      自己把自己加进白名单；职位跟邀请码对不上就插不进去。
--   c) NO_CODE_EMAIL 这个救援管理员邮箱，不用邀请码也能自己变老板
--      (要跟 index.html 里的 NO_CODE_EMAIL 保持一致，改的话两边都要改)。
--   d) 老板/区域副经理可以任意新增(手动在管理面板加人)。
-- 判断「白名单表是不是真的完全空的」，专门给下面的老板引导用。
-- 一定要用 security definer 绕开 RLS 去查——否则从一个还没在白名单里
-- 的新用户角度看，RLS 本身就会把别人的资料全部隐藏掉，导致他看到的
-- 永远是「空的」，谁都能借着这条规则把自己插成 owner。
create or replace function public.erp_users_is_empty()
returns boolean
language sql security definer set search_path = public stable
as $$
  select not exists(select 1 from public.erp_users);
$$;

create policy "erp_users insert self via invite or admin"
  on public.erp_users for insert
  to authenticated
  with check (
    is_admin()
    or (
      email = my_email()
      and (
        (role = 'owner' and public.erp_users_is_empty())
        or (role = 'owner' and email = 'yxchong3@gmail.com')
        or (
          role = public.invite_role(auth.jwt()->'user_metadata'->>'invite_code')
          and outlet = public.invite_outlet(auth.jwt()->'user_metadata'->>'invite_code')
        )
      )
    )
  );

-- 改/删：只有老板/区域副经理能改别人的职位、分店、启用状态。
create policy "erp_users update admin only"
  on public.erp_users for update
  to authenticated
  using (is_admin())
  with check (is_admin());

create policy "erp_users delete admin only"
  on public.erp_users for delete
  to authenticated
  using (is_admin());

-- ========== 第 4 部分：erp_store 业务数据 —— 白名单以外的人一律不能碰 ==========
drop policy if exists "erp_store authed full access" on public.erp_store;
drop policy if exists "erp_store authed access" on public.erp_store;
-- 按 key 的角色/分店规则见 store-lock.sql（这里是同一份，单独跑 store-lock.sql 也行）
create or replace function public.erp_key_ok(k text, writing boolean)
returns boolean
language plpgsql
security definer set search_path = public
stable
as $$
declare
  r   text;
  o   text;
  eo  text;   -- 这个人「所属的店」(中央角色固定是 ck)
  src text;
  dst text;
begin
  if k is null then return false; end if;
  select u.role, u.outlet into r, o
    from public.erp_users u
   where u.email = public.my_email() and u.active = true;
  if r is null then return false; end if;
  if r in ('owner','hrmgr') then return true; end if;
  eo := case when r in ('ckmgr','ckstaff') then 'ck' else o end;

  if k like 'erpv2:payroll:%' then
    if writing then return false; end if;
    return r = 'outletmgr' and k = 'erpv2:payroll:' || o;   -- 备份 key(erpv2:payroll:bak:…)不会等于这个
  end if;

  if k in ('erpv2:orders','erpv2:ckorder') then return true; end if;

  if k = 'erpv2:roleperms' then return (not writing) or r = 'area'; end if;

  if k ~ '^erpv2:(b([1-9]|1[01])|ck)$' then
    if r = 'area' then return k <> 'erpv2:ck'; end if;
    return eo is not null and k = 'erpv2:' || eo;
  end if;

  if k ~ '^erpv2:xfer:[a-z0-9]+:[a-z0-9]+$' then
    if r = 'area' then return true; end if;
    src := split_part(k, ':', 3);
    dst := split_part(k, ':', 4);
    if writing then return eo is not null and src = eo; end if;
    return eo is not null and (src = eo or dst = eo);
  end if;

  return false;
end;
$$;

drop policy if exists "erp_store whitelisted only" on public.erp_store;
drop policy if exists "erp_store whitelisted payroll-locked" on public.erp_store;
drop policy if exists "erp_store key-locked" on public.erp_store;
create policy "erp_store key-locked"
  on public.erp_store for all
  to authenticated
  using (public.is_whitelisted() and public.erp_key_ok(key, false))
  with check (public.is_whitelisted() and public.erp_key_ok(key, true));


-- ========== 第 5 部分：推送订阅表 —— 同样收紧 ==========
-- 用 DO 块包一层：如果你还没跑过 push-schema.sql 建这张表，就自动跳过，不会报错。
do $$
begin
  if to_regclass('public.erp_push_subs') is not null then
    execute 'drop policy if exists "erp_push_subs authed" on public.erp_push_subs';
    execute 'drop policy if exists "erp_push_subs whitelisted only" on public.erp_push_subs';
    execute $p$create policy "erp_push_subs whitelisted only"
      on public.erp_push_subs for all
      to authenticated
      using (is_whitelisted())
      with check (is_whitelisted())$p$;
  end if;
end $$;

-- ========== 第 6 部分：付款收据储存桶 receipts —— 同样收紧 ==========
-- 同样：如果你还没跑过 STORAGE_SETUP_MENGKEE.md 建 receipts 桶，就自动跳过。
do $$
begin
  if exists(select 1 from storage.buckets where id = 'receipts') then
    execute 'drop policy if exists "receipts authed all" on storage.objects';
    execute 'drop policy if exists "receipts whitelisted only" on storage.objects';
    execute $p$create policy "receipts whitelisted only"
      on storage.objects for all
      to authenticated
      using (bucket_id = 'receipts' and public.is_whitelisted())
      with check (bucket_id = 'receipts' and public.is_whitelisted())$p$;
  end if;
end $$;

-- ============================================================
-- 跑完这份之后，务必再去 Supabase 后台做这一步（SQL 做不到，要手动点）：
-- Authentication → Providers → Email → 把「Confirm email」打开(启用)。
-- 这样注册时会先发确认邮件，没验证邮箱前进不了系统，
-- 避免有人用假邮箱/别人的邮箱狂开账号硬闯白名单流程。
-- ============================================================
