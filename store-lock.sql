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
--       区域副经理 area：b1~b11 全部（不含 ck）
--       店面经理/店长/厨师长/员工：只有自己那间店
--       中央经理/中央员工：只有 ck
--   erpv2:payroll:*  薪资记录：owner/hrmgr 读写；店面经理只读本店的 erpv2:payroll:<店>；其他人读不到也写不进
--   erpv2:orders、erpv2:ckorder  订单 / 中央厨房订货表：所有白名单账号可读写
--   erpv2:roleperms  岗位权限：所有人可读；只有 owner/hrmgr/area 能写
--   erpv2:xfer:<发出店>:<收到店>  跨店调拨单：只有「发出店」能写；发出店和收到店能读（owner/hrmgr/area 都可）
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

-- ===== 跑之前先检查：这条应该是 0 行（有结果就是有账号的分店栏位是空的/不对，先去「设置→账号权限」改好）=====
-- select email, role, outlet from public.erp_users
--  where active = true
--    and role in ('outletmgr','manager','headchef','staff')
--    and (outlet is null or outlet not in ('b1','b2','b3','b4','b5','b6','b7','b8','b9','b10','b11'));

-- ===== 如果出问题要还原成「白名单内都能读写」(救急用)，跑下面这几行 =====
-- drop policy if exists "erp_store key-locked" on public.erp_store;
-- create policy "erp_store whitelisted only" on public.erp_store for all to authenticated
--   using (public.is_whitelisted()) with check (public.is_whitelisted());
