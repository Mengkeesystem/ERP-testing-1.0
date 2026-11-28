-- ============================================================
-- 明记 ERP · 数据按角色/分店上锁（BUILD 1102mk69 起；取代之前的 payroll-lock.sql）
-- 用法：Supabase 控制台 → SQL Editor → New query → 粘贴全部 → Run。可重复运行。
-- 前提：已经跑过 security-hardening.sql（需要 is_whitelisted()/my_email()）。
--
-- ⚠️ 跑之前的顺序（很重要）：
--   1) 先让网页更新到 1102mk69 以上，再用【老板或人事经理】账号登录一次（会自动把订货表搬出中央厨房整包）；
--   2) 先跑文末「跑之前先检查」那条查询，确认没有账号的分店栏位是空的；
--   3) 然后才跑这份。
--
-- 规则（erp_store 里每个 key）：
--   erpv2:b1 … b11、erpv2:ck  分店/中央厨房整包
--       老板 owner / 人事经理 hrmgr：全部
--       运营经理 area：b1~b11 全部（不含 ck）
--       店面经理/店长/厨师长/员工：只有自己那间店
--       中央经理/中央员工：只有 ck
--   erpv2:payroll:*  薪资记录：owner/hrmgr 读写；店面经理只读本店的 erpv2:payroll:<店>；其他人读不到也写不进
--   erpv2:pii:<店>  员工个人资料（身份证/电话/住址/紧急联络人，mk170 起从分店整包里拆出来）：
--       读＝执行董事/人事经理/运营经理（不含 ck）/本店店面经理；写＝执行董事/人事经理/运营经理（不含 ck）；其他岗位（店长/厨师长/员工等）读不到也写不进
--   erpv2:orders  订货单：所有白名单账号可读写，但由下面的触发器 erp_orders_guard 把关（只有执行董事/人事经理/运营经理能确认/拒绝/删除/退回；
--       分店只能新增「待确认」的单、取消自己店待确认的单、收自己店的货；中央厨房角色能标发货；确认之后的数量/单价锁定，只有「已收」和进度记录能变）
--   erpv2:ckorder  中央厨房订货表：所有白名单账号可读写
--   erpv2:roleperms  岗位权限：所有人可读；只有 owner/hrmgr/area 能写
--   erpv2:req:<发起店>:<被申请店>:<编号>  跨店调拨申请：双方店面都能读写；谁能批准由下面的触发器 erp_req_guard 把关
--   其他任何 key：只有 owner/hrmgr
-- ============================================================
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
create policy "erp_store key-locked"
  on public.erp_store for all
  to authenticated
  using (public.is_whitelisted() and public.erp_key_ok(key, false))
  with check (public.is_whitelisted() and public.erp_key_ok(key, true));

-- ===== 跑之前先检查：这条应该是 0 行（有结果就是有账号的分店栏位是空的/不对，先去「设置→账号权限」改好）=====
-- select email, role, outlet from public.erp_users
--  where active = true
--    and role in ('outletmgr','manager','headchef','staff')
--    and (outlet is null or outlet not in ('b1','b2','b3','b4','b5','b6','b7','b8','b9','b10','b11'));

-- ===== 如果出问题要还原成「白名单内都能读写」(救急用)，跑下面这几行 =====
-- drop policy if exists "erp_store key-locked" on public.erp_store;
-- create policy "erp_store whitelisted only" on public.erp_store for all to authenticated
--   using (public.is_whitelisted()) with check (public.is_whitelisted());
