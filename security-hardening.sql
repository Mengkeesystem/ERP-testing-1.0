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

-- 读：自己一定能读到自己那一行(登录要用)；老板/运营经理能读全部(管理面板要用)。
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
--   d) 老板/运营经理可以任意新增(手动在管理面板加人)。
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

-- 改/删：只有老板/运营经理能改别人的职位、分店、启用状态。
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

  -- 员工个人资料：读写规则见文件头。备份 key(erpv2:pii:bak:…)不匹配这条，落到最后的 false（只有执行董事/人事经理）
  if k ~ '^erpv2:pii:(b([1-9]|1[01])|ck)$' then
    if r = 'area' then return k <> 'erpv2:pii:ck'; end if;
    if writing then return false; end if;
    return r = 'outletmgr' and k = 'erpv2:pii:' || o;
  end if;

  -- 营业额与开销：读写规则见文件头。备份 key(erpv2:fin:bak:…)不匹配这条，落到最后的 false（只有执行董事/人事经理）
  if k ~ '^erpv2:fin:(b([1-9]|1[01])|ck)$' then
    if r = 'area' then return k <> 'erpv2:fin:ck'; end if;
    if r in ('outletmgr','manager','ckmgr') then return eo is not null and k = 'erpv2:fin:' || eo; end if;
    if r = 'headchef' then return (not writing) and eo is not null and k = 'erpv2:fin:' || eo; end if;
    return false;
  end if;

  if k in ('erpv2:orders','erpv2:ckorder') then return true; end if;

  if k = 'erpv2:roleperms' then return (not writing) or r = 'area'; end if;

  if k ~ '^erpv2:(b([1-9]|1[01])|ck)$' then
    if r = 'area' then return k <> 'erpv2:ck'; end if;
    return eo is not null and k = 'erpv2:' || eo;
  end if;

  if k ~ '^erpv2:req:[a-z0-9]+:[a-z0-9]+:[A-Za-z0-9_-]+$' then
    if r = 'area' then return true; end if;
    src := split_part(k, ':', 3);
    dst := split_part(k, ':', 4);
    return eo is not null and (src = eo or dst = eo);
  end if;

  return false;
end;
$$;

-- ===== 跨店调拨申请的把关（触发器）=====
-- 规则：① 新申请只能由「发起店」建立，而且一定是待批准(pending)；
--       ② 只有「被申请店」(或老板/人事经理/运营经理)能把 pending 改成 approved / rejected；
--       ③ 已批准/已拒绝的申请不能再被改动；发起店只能撤回 pending、移除 rejected。
create or replace function public.erp_req_guard()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  k   text;
  r   text;
  o   text;
  eo  text;
  req text;
  cnt text;
  olds text;
  news text;
begin
  k := case when tg_op = 'DELETE' then old.key else new.key end;
  if k is null or k not like 'erpv2:req:%' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  select u.role, u.outlet into r, o
    from public.erp_users u
   where u.email = public.my_email() and u.active = true;
  if r is null then raise exception '不在白名单'; end if;
  if r in ('owner','hrmgr','area') then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  eo  := case when r in ('ckmgr','ckstaff') then 'ck' else o end;
  req := split_part(k, ':', 3);
  cnt := split_part(k, ':', 4);

  if tg_op = 'INSERT' then
    -- upsert 到已存在的 key 时，行级 BEFORE INSERT 也会先跑一次；这种情况交给后面的 UPDATE 规则判断
    if exists(select 1 from public.erp_store s where s.key = new.key) then return new; end if;
    if eo is distinct from req then raise exception '只有发起申请的店面才能新增调拨申请'; end if;
    if coalesce(new.value->>'status','') <> 'pending' then raise exception '新的调拨申请必须是待批准状态'; end if;
    return new;
  elsif tg_op = 'UPDATE' then
    olds := coalesce(old.value->>'status','');
    news := coalesce(new.value->>'status','');
    if olds = 'pending' and news in ('approved','rejected') then
      if eo is distinct from cnt then raise exception '只有被申请的店面才能批准或拒绝'; end if;
      if r not in ('outletmgr','manager','headchef','ckmgr') then raise exception '你的岗位不能批准或拒绝调拨申请'; end if;   -- 员工/中央员工只能看，不能批
    elsif olds = 'pending' and news = 'pending' then
      if eo is distinct from req then raise exception '只有发起申请的店面才能修改申请'; end if;
    else
      raise exception '已处理的调拨申请不能再修改';
    end if;
    return new;
  else  -- DELETE
    if eo is distinct from req or coalesce(old.value->>'status','') not in ('pending','rejected') then
      raise exception '只有发起店能撤回待批准/移除被拒绝的申请';
    end if;
    return old;
  end if;
end;
$$;
drop trigger if exists erp_req_guard on public.erp_store;
create trigger erp_req_guard
  before insert or update or delete on public.erp_store
  for each row execute function public.erp_req_guard();

-- ===== 订货单的把关（触发器，mk170 起）=====
-- 以前 erpv2:orders 所有白名单账号都能随便写，懂技术的人可以自己把订单改成「已确认」、改单价、删单。现在：
--   · 执行董事/人事经理/运营经理：不受限（确认、拒绝、退回、删除都是他们的工作）。
--   · 没有登录身份的写入（SQL 编辑器、服务端）：放行（维护用）。
--   · 其他岗位：不能删订单；新增的单必须是「待确认」、属于自己那间店、不带发票号/确认人/确认时间；
--     不能改发票号/确认人/确认时间；状态只能照网页的规矩变：取消自己店「待确认」的单、收自己店「已确认/已发货/部分收货」的货
--     （变成部分收货/已收货）、中央厨房角色把「已确认」标成「已发货」；
--     订货单所属的店面不能改；订单一旦不是「待确认」，供应商和每一行的订货数量/单价/品名就锁定，只有「已收数量」和进度记录（history）能变。
create or replace function public.erp_strip_rcv(a jsonb)
returns jsonb
language sql immutable
as $$
  select coalesce(jsonb_agg(e - 'rcv' order by ord), '[]'::jsonb)
    from jsonb_array_elements(case when jsonb_typeof(a) = 'array' then a else '[]'::jsonb end) with ordinality as t(e, ord)
   where jsonb_typeof(e) = 'object';
$$;

create or replace function public.erp_orders_guard()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  r    text;
  o    text;
  eo   text;
  oldv jsonb;
  ord  jsonb;
  oo   jsonb;
  ost  text;
  nst  text;
  oout text;
  mine boolean;
  ok   boolean;
begin
  if tg_op = 'DELETE' then return old; end if;
  if new.key is distinct from 'erpv2:orders' then return new; end if;
  select u.role, u.outlet into r, o
    from public.erp_users u
   where u.email = public.my_email() and u.active = true;
  if r is null then return new; end if;                             -- 没有登录身份（SQL 编辑器/服务端）：放行
  if r in ('owner','hrmgr','area') then return new; end if;
  if tg_op = 'INSERT' and exists(select 1 from public.erp_store s where s.key = new.key) then return new; end if;   -- upsert 到已有 key：交给 UPDATE 规则
  eo := case when r in ('ckmgr','ckstaff') then 'ck' else o end;
  oldv := case when tg_op = 'UPDATE' and jsonb_typeof(old.value) = 'array' then old.value else '[]'::jsonb end;
  if jsonb_typeof(new.value) <> 'array' then raise exception '订货单资料格式不对'; end if;

  for ord in select x from jsonb_array_elements(new.value) x loop
    oo := (select y from jsonb_array_elements(oldv) y where y->>'id' = ord->>'id' limit 1);
    if oo is null then
      -- 新订单
      if coalesce(ord->>'status','pending') <> 'pending' then raise exception '新订货单必须是待确认状态'; end if;
      if ord->>'outlet' is distinct from eo then raise exception '只能为自己的店面下订货单'; end if;
      if nullif(ord->>'invoiceNo','') is not null or nullif(ord->>'confirmedAt','') is not null or nullif(ord->>'confirmedBy','') is not null then
        raise exception '新订货单不能带发票号/确认人';
      end if;
    else
      if (ord->>'invoiceNo') is distinct from (oo->>'invoiceNo')
         or (ord->>'confirmedAt') is distinct from (oo->>'confirmedAt')
         or (ord->>'confirmedBy') is distinct from (oo->>'confirmedBy') then
        raise exception '只有运营经理以上能改发票号/确认人';
      end if;
      ost := coalesce(oo->>'status','pending');
      nst := coalesce(ord->>'status','pending');
      if (ord->>'outlet') is distinct from (oo->>'outlet') then raise exception '订货单所属的店面不能改'; end if;   -- 防止先把单「改成自己店的」再动手
      if nst <> ost then
        oout := oo->>'outlet';            -- 用「原来」的店面判断是不是自己店的单（不看这次写进来的）
        mine := (oout is null or oout = eo);
        ok := (ost = 'pending' and nst = 'cancelled' and mine)
           or (ost in ('confirmed','shipped','partial') and nst in ('partial','received') and mine)
           or (ost in ('confirmed','shipped') and nst = 'shipped' and r in ('ckmgr','ckstaff'));
        if not ok then raise exception '订货单状态只能由有权限的人修改（这一步没有权限）'; end if;
      end if;
      if ost <> 'pending' then
        if (ord->>'supplier') is distinct from (oo->>'supplier') then raise exception '订单确认之后，供应商不能再改'; end if;
        if public.erp_strip_rcv(ord->'lines') is distinct from public.erp_strip_rcv(oo->'lines')
           or public.erp_strip_rcv(ord->'uniform') is distinct from public.erp_strip_rcv(oo->'uniform') then
          raise exception '订单确认之后，订货数量和单价不能再改（只有运营经理以上可以）';
        end if;
      end if;
    end if;
  end loop;

  for oo in select y from jsonb_array_elements(oldv) y loop
    if not exists(select 1 from jsonb_array_elements(new.value) z where z->>'id' = oo->>'id') then
      raise exception '只有运营经理以上能删除订货单';
    end if;
  end loop;
  return new;
end;
$$;
drop trigger if exists erp_orders_guard on public.erp_store;
create trigger erp_orders_guard
  before insert or update on public.erp_store
  for each row when (new.key = 'erpv2:orders') execute function public.erp_orders_guard();

drop policy if exists "erp_store whitelisted only" on public.erp_store;
drop policy if exists "erp_store whitelisted payroll-locked" on public.erp_store;
drop policy if exists "erp_store key-locked" on public.erp_store;
-- ⚠️ 为什么不能写 for all：Postgres 的 DELETE 只看 using、不看 with check。
--    以前 for all + using(erp_key_ok(key,false))＝「能读就能删」，任何账号都能把全公司岗位权限、订货单、自己店整包、（店面经理）本店薪资整条删掉。
--    所以拆成四条：增/改要「能写」，删除另用 erp_del_ok（只有执行董事/人事经理；运营经理只能删岗位权限/订货单；调拨申请交给 erp_req_guard 判断）。
create or replace function public.erp_del_ok(k text)
returns boolean
language plpgsql
security definer set search_path = public
stable
as $$
declare r text;
begin
  if k is null then return false; end if;
  select u.role into r from public.erp_users u where u.email = public.my_email() and u.active = true;
  if r is null then return false; end if;
  if r in ('owner','hrmgr') then return true; end if;
  if k like 'erpv2:req:%' then return public.erp_key_ok(k, true); end if;   -- 发起店撤回/移除：还要过 erp_req_guard
  if r = 'area' then return k in ('erpv2:roleperms','erpv2:orders','erpv2:ckorder'); end if;
  return false;
end;
$$;
drop policy if exists "erp_store anon full access" on public.erp_store;
drop policy if exists "erp_store authed full access" on public.erp_store;
drop policy if exists "erp_store authed access" on public.erp_store;
drop policy if exists "erp_store whitelisted only" on public.erp_store;
drop policy if exists "erp_store key-locked" on public.erp_store;
drop policy if exists "erp_store key-locked select" on public.erp_store;
drop policy if exists "erp_store key-locked insert" on public.erp_store;
drop policy if exists "erp_store key-locked update" on public.erp_store;
drop policy if exists "erp_store key-locked delete" on public.erp_store;
create policy "erp_store key-locked select"
  on public.erp_store for select to authenticated
  using (public.is_whitelisted() and public.erp_key_ok(key, false));
create policy "erp_store key-locked insert"
  on public.erp_store for insert to authenticated
  with check (public.is_whitelisted() and public.erp_key_ok(key, true));
create policy "erp_store key-locked update"
  on public.erp_store for update to authenticated
  using (public.is_whitelisted() and public.erp_key_ok(key, false))
  with check (public.is_whitelisted() and public.erp_key_ok(key, true));
create policy "erp_store key-locked delete"
  on public.erp_store for delete to authenticated
  using (public.is_whitelisted() and public.erp_del_ok(key));


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


-- ===== 账号表 erp_users 的把关（触发器）+ 推送订阅 + 付款收据（mk179）=====
-- ① erp_users：以前 is_admin() 包含运营经理，所以运营经理能把自己/别人改成执行董事，甚至删掉执行董事账号。现在：
--    · 只有执行董事/人事经理能新增、修改、删除「执行董事/人事经理」的账号（也只有他们能把别人设成这两个岗位）；
--    · 运营经理只能管运营经理以下的账号；
--    · 任何人（SQL 编辑器除外）都不能把最后一位在用的执行董事改走/停用/删掉；
--    · 没有登录身份的写入（SQL 编辑器/服务端）放行（维护用）；还不在名单里的人自己注册（邀请码/第一位）交给原来的 insert 规则。
create or replace function public.erp_users_guard()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare cr text; me text;
begin
  me := public.my_email();
  if me is null or me = '' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  select u.role into cr from public.erp_users u where u.email = me and u.active = true;
  if cr is null then
    if tg_op = 'DELETE' then return old; else return new; end if;   -- 还没在名单里的人：只可能走 insert 的邀请码规则，其余有 RLS 挡着
  end if;
  if cr not in ('owner','hrmgr') then
    if tg_op = 'INSERT' and new.role in ('owner','hrmgr') then raise exception '只有执行董事/人事经理能新增执行董事或人事经理账号'; end if;
    if tg_op = 'UPDATE' and (old.role in ('owner','hrmgr') or new.role in ('owner','hrmgr')) then raise exception '只有执行董事/人事经理能修改执行董事或人事经理账号'; end if;
    if tg_op = 'DELETE' and old.role in ('owner','hrmgr') then raise exception '只有执行董事/人事经理能删除执行董事或人事经理账号'; end if;
  end if;
  if tg_op in ('UPDATE','DELETE') and old.role = 'owner' and old.active = true
     and (tg_op = 'DELETE' or new.role <> 'owner' or new.active is distinct from true)
     and not exists(select 1 from public.erp_users x where x.role = 'owner' and x.active = true and x.email <> old.email) then
    raise exception '至少要保留一位在用的执行董事';
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
drop trigger if exists erp_users_guard on public.erp_users;
create trigger erp_users_guard
  before insert or update or delete on public.erp_users
  for each row execute function public.erp_users_guard();

-- ② 手机推送订阅 erp_push_subs：每个人只能读写自己邮箱的订阅（以前白名单里谁都能删别人的、也能自己写一条「执行董事」的订阅来收新订单通知）。
--    发推送的云函数用服务端身份，不受这条限制；它会以 erp_users 里的真实岗位为准，不信这张表里的 role 栏。
do $$
begin
  if to_regclass('public.erp_push_subs') is not null then
    execute 'drop policy if exists "erp_push_subs authed" on public.erp_push_subs';
    execute 'drop policy if exists "erp_push_subs whitelisted only" on public.erp_push_subs';
    execute 'drop policy if exists "erp_push_subs own select" on public.erp_push_subs';
    execute 'drop policy if exists "erp_push_subs own insert" on public.erp_push_subs';
    execute 'drop policy if exists "erp_push_subs own update" on public.erp_push_subs';
    execute 'drop policy if exists "erp_push_subs own delete" on public.erp_push_subs';
    execute $p$create policy "erp_push_subs own select" on public.erp_push_subs for select to authenticated
      using (public.is_whitelisted() and lower(coalesce(email,'')) = public.my_email())$p$;
    execute $p$create policy "erp_push_subs own insert" on public.erp_push_subs for insert to authenticated
      with check (public.is_whitelisted() and lower(coalesce(email,'')) = public.my_email())$p$;
    execute $p$create policy "erp_push_subs own update" on public.erp_push_subs for update to authenticated
      using (public.is_whitelisted() and lower(coalesce(email,'')) = public.my_email())
      with check (public.is_whitelisted() and lower(coalesce(email,'')) = public.my_email())$p$;
    execute $p$create policy "erp_push_subs own delete" on public.erp_push_subs for delete to authenticated
      using (public.is_whitelisted() and lower(coalesce(email,'')) = public.my_email())$p$;
  end if;
end $$;

-- ②b 手机共用时（B 在 A 的手机上登录再点「开启通知」），浏览器的订阅编号(endpoint)不变，直接 upsert 会撞到 A 那一行、被上面的「只能改自己的」挡住。
--    所以登记/取消登记走这两个函数：以数据库里的真实账号和岗位为准，写成当前登录的人（role 不信网页传来的）。
create or replace function public.erp_push_register(p_endpoint text, p_sub jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare me text; r text;
begin
  me := public.my_email();
  select u.role into r from public.erp_users u where u.email = me and u.active = true;
  if r is null then raise exception '不在白名单'; end if;
  if p_endpoint is null or length(p_endpoint) < 10 or p_sub is null then raise exception '订阅无效'; end if;
  insert into public.erp_push_subs(endpoint, sub, email, role, updated_at) values (p_endpoint, p_sub, me, r, now())
  on conflict (endpoint) do update set sub = excluded.sub, email = excluded.email, role = excluded.role, updated_at = now();
end;
$$;
create or replace function public.erp_push_unregister(p_endpoint text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare me text;
begin
  me := public.my_email();
  if not public.is_whitelisted() then raise exception '不在白名单'; end if;
  delete from public.erp_push_subs where endpoint = p_endpoint and (lower(coalesce(email,'')) = me or coalesce(email,'') = '');
end;
$$;
revoke all on function public.erp_push_register(text, jsonb) from public, anon;
revoke all on function public.erp_push_unregister(text) from public, anon;
grant execute on function public.erp_push_register(text, jsonb) to authenticated;
grant execute on function public.erp_push_unregister(text) to authenticated;

-- ③ 付款收据储存桶 receipts：只有有「应付账款」权限的岗位（执行董事/人事经理/运营经理/店面经理/店长/厨师长/中央经理）；注意：这是写死在数据库里的，之后在「岗位权限编辑」给别的岗位加了「应付账款」，数据库不会跟着放行，要改 erp_receipt_ok能看、传；删除只给执行董事/人事经理/运营经理。
create or replace function public.erp_receipt_ok(del boolean)
returns boolean
language plpgsql
security definer set search_path = public
stable
as $$
declare r text;
begin
  select u.role into r from public.erp_users u where u.email = public.my_email() and u.active = true;
  if r is null then return false; end if;
  if del then return r in ('owner','hrmgr','area'); end if;
  return r in ('owner','hrmgr','area','outletmgr','manager','headchef','ckmgr');   -- 跟网页「应付账款(ap)」权限一致：中央经理也有
end;
$$;
do $$
begin
  if exists(select 1 from storage.buckets where id = 'receipts') then
    execute 'drop policy if exists "receipts authed all" on storage.objects';
    execute 'drop policy if exists "receipts whitelisted only" on storage.objects';
    execute 'drop policy if exists "receipts role select" on storage.objects';
    execute 'drop policy if exists "receipts role insert" on storage.objects';
    execute 'drop policy if exists "receipts role update" on storage.objects';
    execute 'drop policy if exists "receipts role delete" on storage.objects';
    execute $p$create policy "receipts role select" on storage.objects for select to authenticated
      using (bucket_id = 'receipts' and public.erp_receipt_ok(false))$p$;
    execute $p$create policy "receipts role insert" on storage.objects for insert to authenticated
      with check (bucket_id = 'receipts' and public.erp_receipt_ok(false))$p$;
    execute $p$create policy "receipts role update" on storage.objects for update to authenticated
      using (bucket_id = 'receipts' and public.erp_receipt_ok(false))
      with check (bucket_id = 'receipts' and public.erp_receipt_ok(false))$p$;
    execute $p$create policy "receipts role delete" on storage.objects for delete to authenticated
      using (bucket_id = 'receipts' and public.erp_receipt_ok(true))$p$;
  end if;
end $$;

-- ============================================================
-- 跑完这份之后，务必再去 Supabase 后台做这一步（SQL 做不到，要手动点）：
-- Authentication → Providers → Email → 把「Confirm email」打开(启用)。
-- 这样注册时会先发确认邮件，没验证邮箱前进不了系统，
-- 避免有人用假邮箱/别人的邮箱狂开账号硬闯白名单流程。
-- ============================================================
