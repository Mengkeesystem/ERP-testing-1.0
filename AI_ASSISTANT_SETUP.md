# AI 助手（问 AI）· 设定步骤（业主在 Supabase 上做，约 3 分钟）

前提：你已经为「拍照识别」设好了 `ANTHROPIC_API_KEY`（同一个 key，不用再建）。

1. Supabase → **Edge Functions → Deploy a new function**，名称必须是 `ask-ai`，把仓库里 `supabase/functions/ask-ai/index.ts` 全部内容贴上去 → Deploy。
2. 这个函数的 **Verify JWT 关掉**（函数自己会验证登录账号）。
3. 检查：浏览器打开 `https://kmcdokwiyetlmsrdlgqw.supabase.co/functions/v1/ask-ai?health=1`，看到 `{"ok":true}` 就设好了。
4. （可选）想换模型：Secrets 里加 `AI_MODEL`，值＝模型代号；不设就用 `claude-sonnet-5-5`。

## 怎么用
ERP 右上角点「AI」（手机在「⋯」菜单里；运营健康页右上角也有「问 AI」），输入问题或点推荐问题。
- AI 只会看到**这间店的汇总数字**（成本、进货、价格变动、库存、报废、订货单、运营健康检查；老板/运营经理还有各分店对比），**不含**员工资料、邮箱、薪资。
- 它只根据这些数字回答，没有的资料会说「系统里没有」，并告诉你该去哪一页补。
- 回答只供参考，重要的数字请回原页面核对。

## 费用
每问一次大约 4,000–10,000 个输入 token + 几百个输出 token；用 Sonnet 5.5 估算约 **USD 0.01–0.03（RM 0.05–0.15）一次**（按 Anthropic 官网价：输入 $2/百万、输出 $10/百万，是估算，不是账单）。每人每分钟最多问 10 次。
