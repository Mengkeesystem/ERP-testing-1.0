# 明记 手机推送设置 (Web Push)

明记有自己的一套 VAPID 密钥（下面），与牛室完全独立。网页里已内置**公钥**；
**私钥只放在明记自己的 Supabase Function secret 里，绝不写进网页。**

## 明记 VAPID 密钥
- **VAPID_PUBLIC**（已写进 index.html）：
  `BPGwb8azat026wZ9320MDLBLUpn4JYbsxkJ39knCMKrffomyhC1qKlYJbOwkZ294Bjo66zKA_e-Aw5nkAnZOUng`
- **VAPID_PRIVATE**：只放在 Supabase Function Secrets，**绝不写进本仓库**（旧私钥已于 2026-11-02 外泄作废，已换新密钥对）。

## 部署步骤（在明记自己的 Supabase 项目 kmcdokwiyetlmsrdlgqw）
1. **建订阅表**：SQL Editor 运行 `push-schema.sql`。
2. **设 secrets**：Project → Edge Functions → Secrets，加：
   - `VAPID_PUBLIC` = 上面的公钥
   - `VAPID_PRIVATE` = 新私钥（由业主保管，不在仓库里）
   - `VAPID_SUBJECT` = `mailto:你的邮箱`
3. **部署函数**：把 `supabase/functions/send-order-push/` 部署为名为 `send-order-push` 的 Edge Function
   （`supabase functions deploy send-order-push`）。
4. 完成后，App 里「开启通知」即可收到新订单手机推送。未部署前，App 仍可正常用（只是没有手机推送）。
