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

## 安全说明（2026-11-02 起）
- 部署时 **Verify JWT 仍然保持关闭**（函数自己会验证登录令牌）。
- 函数只接受「已登录、而且在 ERP 白名单里且启用」的账号；其余一律 401。
- 调拨通知（带 `outlet`）必须真的有一张连着两间店的调拨申请才能发（老板/人事经理/区域副经理除外）。
- 标题/内容限长并去掉 `<` `>`；图标固定；同一账号每分钟最多 20 次；CORS 只允许 `https://mengkeesystem.github.io`。
- **健康检查**：`GET https://<项目>.supabase.co/functions/v1/send-order-push?health=1` → `{"ok":true}`；
  有问题回 503 `{"ok":false,"problems":[...]}`。只检查设定，**绝不发推送**，可给监控用。
