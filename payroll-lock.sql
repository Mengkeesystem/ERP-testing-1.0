-- ============================================================
-- 明记 ERP · 薪资记录上锁（第 1 步，BUILD 1102mk68 起）
-- 用法：Supabase 控制台 → SQL Editor → New query → 粘贴全部 → Run。可重复运行。
-- 前提：已经跑过 security-hardening.sql（需要 is_whitelisted()/my_email()）。
--
-- 做什么：erp_store 里 key 以 'erpv2:payroll:' 开头的记录（薪资 + 备份）
--   * 读：老板 owner / 人事经理 hrmgr 全部可读；店面经理 outletmgr 只能读「自己那间店」的 erpv2:payroll:<店>
--   * 写：只有 owner / hrmgr
--   * 其他所有角色（含区域副经理、店长、厨师长、员工、中央）：读不到、写不进
-- 其他 key（分店整包、订货单、岗位权限…）规则不变，照旧「白名单内的人都能读写」。
-- 分店之间的隔离是下一步，这份不动它。
-- ============================================================
create or replace function public.erp_key_ok(k text, writing boolean)
returns boolean
language plpgsql
security definer set search_path = public
stable
as $$
declare
  r text;
  o text;
begin
  if k is null or k not like 'erpv2:payroll:%' then
    return true;                       -- 不是薪资 key：沿用原本的规则
  end if;
  select u.role, u.outlet into r, o
    from public.erp_users u
   where u.email = public.my_email() and u.active = true;
  if r is null then return false; end if;
  if r in ('owner','hrmgr') then return true; end if;
  if writing then return false; end if;
  return r = 'outletmgr' and k = 'erpv2:payroll:' || o;   -- 备份 key(erpv2:payroll:bak:…)不会等于这个，所以店面经理读不到
end;
$$;

drop policy if exists "erp_store whitelisted only" on public.erp_store;
drop policy if exists "erp_store whitelisted payroll-locked" on public.erp_store;
create policy "erp_store whitelisted payroll-locked"
  on public.erp_store for all
  to authenticated
  using (public.is_whitelisted() and public.erp_key_ok(key, false))
  with check (public.is_whitelisted() and public.erp_key_ok(key, true));

-- ===== 如果要还原成「白名单内都能读写」(出问题时救急用)，跑下面这几行 =====
-- drop policy if exists "erp_store whitelisted payroll-locked" on public.erp_store;
-- create policy "erp_store whitelisted only" on public.erp_store for all to authenticated
--   using (public.is_whitelisted()) with check (public.is_whitelisted());
