# 手机推送新增功能 · 设定步骤（业主在 Supabase 上做，约 10 分钟）

新增两种手机推送：
1. **订货单状态变化**：确认/拒绝/发货 → 通知下单那间店；部分收货/已收货 → 通知老板/副经理；取消 → 两边。（要重新部署函数）
2. **每日提醒**：每天早上 9 点，每间店的店长们收到「今天要处理 N 件事」（盘点逾期 / 进货几天没录 / 库存为负 / 等收货）；老板/副经理收一条汇总（含待确认订货单）。（要重新部署函数 + 设一个 Secret + 跑一段 SQL）

## 步骤
1. **重新部署函数**：Supabase → Edge Functions → `send-order-push` → 把仓库里 `supabase/functions/send-order-push/index.ts` 全部内容贴上去 → Deploy。**Verify JWT 保持关闭**。
2. **新增 Secret**：Edge Functions → Secrets → 新增 `CRON_SECRET`，值＝你自己想一串长一点的随机密码（例如 30 个字母数字）。记下来，下一步要用。
3. **排定时任务**：SQL Editor 打开仓库里的 `push-digest-cron.sql`，把 `<换成你的CRON_SECRET>` 换成第 2 步那串密码，运行。（pg_cron / pg_net 免费版可以用；要是提示没权限，到 Database → Extensions 里先把 pg_cron、pg_net 打开。）
4. **检查**：浏览器打开 `https://kmcdokwiyetlmsrdlgqw.supabase.co/functions/v1/send-order-push?health=1`，看到 `{"ok":true,"digest":true}` 就是设好了；`digest:false` ＝第 2 步没设对。
5. **想马上试一次**：SQL Editor 跑 `select net.http_post(url := 'https://kmcdokwiyetlmsrdlgqw.supabase.co/functions/v1/send-order-push', headers := jsonb_build_object('Content-Type','application/json','x-cron-secret','你的密码'), body := '{"kind":"digest"}'::jsonb);`

## 收得到的前提（没变）
- iPhone 要「加到主屏幕」，并在 App 里点「开启本机通知」；通知声音要在系统设置里开。
- 每个人要自己用自己的手机点过一次「开启通知」。
