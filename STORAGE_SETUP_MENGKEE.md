# 🧾 付款收据 存到 Supabase Storage（一次性设置）

作用：店长上传的转账收据，改成存到 Supabase 云端储存，按「分店 / 供应商 / 月份」自动归档，省空间、方便会计查。

## 一步搞定（在 Supabase → SQL Editor 贴上运行）

```sql
-- 1) 建收据储存桶 receipts（私有）
insert into storage.buckets (id, name, public)
  values ('receipts','receipts', false)
  on conflict (id) do nothing;

-- 2) 允许已登录用户 上传 / 读取 / 更新 / 删除 receipts 桶
drop policy if exists "receipts authed all" on storage.objects;
create policy "receipts authed all"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'receipts')
  with check (bucket_id = 'receipts');
```

看到 Success 就完成。之后店长在付款时上传的收据会自动存到：
`receipts / <分店> / <供应商> / <年-月> / <时间>.jpg`

> ⚠️ 上面这条策略是「只要登录过就能读写」，正式上线前记得再跑一次
> `security-hardening.sql`，会把这条收紧成「只有白名单里的人」才能读写。

> 桶设为**私有**；网页查看收据时用「限时签名链接」打开，外人拿不到。
> 若没做这步，系统会自动退回把收据**内嵌**存在资料里（仍可用，只是较占空间）。

## 上传限制
- 只接受 **图片(JPG / PNG)**，**5MB 以下**（上传框已有提示；系统还会自动压缩到约 1400px）。
