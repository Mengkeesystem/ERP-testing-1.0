-- 明记 ERP 账号 + 收据桶 检查（只读，不会改任何东西）
-- 在 Supabase → SQL Editor 新开一个 query，贴上 → Run。结果是一张表，全部列出来给 Claude 看（可截图）。
select 1 as 序, '账号' as 类型, email as 内容, role || ' / ' || coalesce(outlet,'-') || ' / ' || (case when active then '在用' else '已停用' end) as 说明
from public.erp_users where role in ('owner','hrmgr','area') or lower(email) like 'yxchong3%'
union all
select 2, '收据桶', id, '存在（public=' || public::text || '）' from storage.buckets where id ilike '%receipt%'
union all
select 3, '收据桶', '（没有找到名字含 receipt 的桶）', '' where not exists(select 1 from storage.buckets where id ilike '%receipt%')
union all
select 4, '存储规则', policyname, cmd::text from pg_policies where schemaname='storage' and tablename='objects'
order by 1, 2, 3;
