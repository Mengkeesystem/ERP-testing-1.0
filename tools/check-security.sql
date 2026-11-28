-- 明记 ERP 上线前安全检查（只读，不会改任何东西）
-- 用法：Supabase → SQL Editor → 贴上 → 按 Run。结果只有一张表：「结果」那一列全部是 ✅ 就对了；有 ❌ 就截图给 Claude。
-- （Supabase 一次只显示最后一个结果，所以这份把所有检查合成了一张表。）
with c as (
  select 1 as n, '行级安全(RLS)已打开的表（erp_store/erp_users/erp_push_subs/erp_invite_codes）' as 检查项,
         (select count(*) from pg_class where relname in ('erp_store','erp_users','erp_push_subs','erp_invite_codes') and relrowsecurity)::text as 实际, '4' as 应该是
  union all select 2, 'erp_store 的「key-locked」规则条数（select/insert/update/delete）',
         (select count(*) from pg_policies where schemaname='public' and tablename='erp_store' and policyname like 'erp\_store key-locked %')::text, '4'
  union all select 3, 'erp_store 全部规则条数（不能有漏网的旧规则）',
         (select count(*) from pg_policies where schemaname='public' and tablename='erp_store')::text, '4'
  union all select 4, 'erp_push_subs 的「own」规则条数',
         (select count(*) from pg_policies where schemaname='public' and tablename='erp_push_subs' and policyname like 'erp\_push\_subs own %')::text, '4'
  union all select 5, 'erp_push_subs 全部规则条数',
         (select count(*) from pg_policies where schemaname='public' and tablename='erp_push_subs')::text, '4'
  union all select 6, '付款收据(receipts)的规则条数（读/传/改/删；没建 receipts 桶＝0 条，算正常）',
         (select count(*) from pg_policies where schemaname='storage' and tablename='objects' and policyname ilike '%receipt%')::text,
         case when exists(select 1 from storage.buckets where id='receipts') then '4' else '0' end
  union all select 7, '分店上锁/把关/推送登记用的函数个数',
         (select count(distinct proname) from pg_proc where proname in ('erp_key_ok','is_whitelisted','is_admin','erp_req_guard','erp_orders_guard','erp_strip_rcv','erp_del_ok','erp_users_guard','erp_receipt_ok','erp_push_register','erp_push_unregister'))::text, '11'
  union all select 8, '触发器个数（erp_req_guard、erp_orders_guard、erp_users_guard）',
         (select count(distinct tgname) from pg_trigger where not tgisinternal and tgname in ('erp_req_guard','erp_orders_guard','erp_users_guard'))::text, '3'
  union all select 9, '漏网的「全部动作(ALL)」宽松规则条数',
         (select count(*) from pg_policies where cmd='ALL' and ((schemaname='public' and tablename like 'erp\_%') or (schemaname='storage' and tablename='objects' and policyname ilike '%receipt%')))::text, '0'
  union all select 10, '在用的执行董事账号数（至少 1 个）',
         (select count(*) from public.erp_users where role='owner' and active=true)::text, '>=1'
)
select 检查项, 实际, 应该是, 结果 from (
  select n, 检查项, 实际, 应该是,
         case when (应该是 = '>=1' and 实际::int >= 1) or 实际 = 应该是 then '✅' else '❌' end as 结果
  from c
  union all
  select 11, '（只供查看）执行董事/人事经理账号：' || coalesce((select string_agg(email || '=' || role, '，' order by role, email) from public.erp_users where role in ('owner','hrmgr') and active=true), '无'), '', '', ''
) t order by n;
