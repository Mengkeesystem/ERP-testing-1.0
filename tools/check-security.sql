-- 明记 ERP 上线前安全检查（只读，不会改任何东西）
-- 在 Supabase → SQL Editor 贴上 → 按 Run。看下面每一段的「应该看到」。

-- ① 这几张表有没有开「行级安全」(RLS)：每一行 rls_on 都应该是 true
select relname as 表名, relrowsecurity as rls_on
from pg_class
where relname in ('erp_store','erp_users','erp_push_subs','erp_invite_codes')
order by relname;

-- ② 权限规则（policy）有没有在：erp_store 应该看到「erp_store key-locked」
select tablename as 表名, policyname as 规则名, cmd as 动作
from pg_policies
where schemaname='public' and tablename in ('erp_store','erp_users','erp_push_subs')
order by tablename, policyname;

-- ③ 分店上锁、调拨申请把关用的函数/触发器在不在：应该看到 6 个函数 + 2 个触发器（erp_req_guard、erp_orders_guard）
select 'function' as 类型, proname as 名字 from pg_proc
where proname in ('erp_key_ok','is_whitelisted','is_admin','erp_req_guard','erp_orders_guard','erp_strip_rcv')
union all
select 'trigger', tgname from pg_trigger where tgname like '%erp_req_guard%' or tgname like '%erp_orders_guard%';
