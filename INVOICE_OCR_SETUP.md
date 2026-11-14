# 进货单拍照识别 · 设定步骤（业主在 Supabase 网页上做，约 5 分钟）

1. 到 https://console.anthropic.com 注册/登入 → **API Keys** → 建一把新 key（复制保管好，只显示一次）；**Billing** 充一点额度（识别一张发票大约几分钱）。
2. Supabase 控制台（明记项目 `kmcdokwiyetlmsrdlgqw`）→ **Edge Functions → Secrets**（或 Project Settings → Edge Functions）新增：
   - 名称 `ANTHROPIC_API_KEY`，值 = 上一步的 key。
   - （可选）`INVOICE_MODEL` = 要用的 Claude 模型代号，不设就用 `claude-sonnet-5-5`。
3. **Edge Functions → Deploy a new function**，名称必须是 `invoice-ocr`，把仓库里 `supabase/functions/invoice-ocr/index.ts` 全部贴进去 → Deploy。
4. 该函数的 **Verify JWT 要关掉**（和 `send-order-push` 一样；函数自己会验证登录账号）。
5. 检查：浏览器打开 `https://kmcdokwiyetlmsrdlgqw.supabase.co/functions/v1/invoice-ocr?health=1`，看到 `{"ok":true}` 就设好了；`ANTHROPIC_API_KEY_not_set` = 第 2 步没做对。

用法：「进货」→ 选供应商 → 按日视图右上「拍照识别」→ 拍发票 → 核对 → 「写入进货单」。
⚠️ **绝不要把 API key 写进仓库/聊天**（仓库是公开的）。
