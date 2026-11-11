# 项目备忘 (CLAUDE.md) — 明记家乡小食店 ERP（Meng Kee ERP）

> 这份是 **明记 ERP** 专用的交接文件（2026-11-02 整理；由两个会话先后写的内容合并而成：「架构 + 近期修复 + 待确认」和「三仓库分工 + SQL + 跟牛室差异 + 安全待办」）。
> 业主分三个对话维护三样东西：**① 明记 ERP（本仓库）　② 牛室 ERP　③ 明记官网**。本文件只讲 ①，换账号/新对话时**先读完「交接总览」**，细节再往下翻。
> ⚠️ 本仓库是**公开**的：绝不能写入 service_role、API Key/Secret、VAPID 私钥、邀请码、密码（见最底「⚠️ 安全待办」，目前已有两处外泄）。

## 🔑 交接总览

### 三个仓库的分工（三份 CLAUDE.md 各管各的）
| | 仓库 | 是什么 | Supabase |
|---|---|---|---|
| ① **明记 ERP（本仓库）** | `Mengkeesystem/ERP-testing-1.0` | 明记（马来西亚中餐小食店，11 间分店 + 中央厨房）的内部 ERP，单文件 `index.html` | 明记自己的项目 `kmcdokwiyetlmsrdlgqw`（Pro）——**同一个项目里还放着官网后台的 `web_*` 表/函数，ERP 的 SQL 不能碰它们** |
| ② 牛室 ERP | `Beefhousesystem/BeefHouse_ERP_1.0` | 牛室（Western buffet 牛排店）的 ERP，**新功能一般先在牛室做，再搬来明记** | 牛室**完全独立**的另一个项目，**绝不能混** |
| ③ 明记官网 | `Mengkeesystem/restoranmengkee` | 客人看的官网：网上点餐/外送/HitPay 付款、员工后台 `admin.html`、订位 | 用明记 ERP 的同一个 Supabase 项目，只用 `web_*` 开头的东西 |

- 官网和 ERP 是**两套独立的代码**，数据也分开存（ERP 用 `erp_store`/`erp_users`/`erp_push_subs`，官网用 `web_orders`/`web_staff`…）。官网相关的事去读官网仓库的 CLAUDE.md，不要在这里改。

### 这是什么
- 单文件 HTML ERP（`index.html` 约 4600 行，**没有构建步骤**）+ `sw.js`（Service Worker，PWA）+ `order-data.js`（中央厨房订货数据，含图片）+ `manifest.webmanifest` + 图标 + `supabase-schema.sql` / `security-hardening.sql` / `push-schema.sql` + `supabase/functions/send-order-push`（手机推送）。
- **当前版本：`BUILD="1111mk82"`**（`index.html` 约 668 行），`sw.js` 的 `SW_VERSION` 要**同步改成一样**（每次改动两处一起 +1，右上角版本角标和强制更新弹窗靠它）。版本号格式 `MMDDmkNN`（mk = 明记）。最后一次提交 2026-09-30。
- 部署：GitHub Pages，**直接推 `main` 就上线**（不开分支、不开 PR），网址 `https://mengkeesystem.github.io/ERP-testing-1.0/`。业主要求跟牛室一样：改完测完直接推。
- 后端 Supabase 项目网址 `https://kmcdokwiyetlmsrdlgqw.supabase.co`；`SUPABASE_ANON_KEY` 是 publishable key（前端公开的，没问题）。**私钥类（service_role、VAPID 私钥）绝对不写进代码/文档**，只放 Supabase Secrets。
- 数据存哪：登录后用 Supabase（`Store.get/set` → `erp_store` 表，key 是 `erpv2:<分店id>`、`erpv2:roleperms`、`erpv2:orders`）；没登录（演示模式）用浏览器本机。代码改了**不会动到数据**（数据在 Supabase，不在 `index.html` 里）。
- **薪资数据单独存放（BUILD 1102mk69 起）**：底薪/津贴/加班/EPF/SOCSO/EIS/人头税/银行资料（`PAY_FIELDS`）+ 薪资发放记录（`payrollRuns`/`payrollCfg`/`payrunMonths`，`PAY_TOP`）不再放在分店整包 `erpv2:<店>`，改存 `erpv2:payroll:<店>`（迁移前的备份在 `erpv2:payroll:bak:<店>`）。数据库规则见 `store-lock.sql`（也已并入 `security-hardening.sql` 第 4 部分）：**owner/hrmgr 读写全部，outletmgr 只读本店，其余角色（含 area）读不到也写不进**。网页载入时（`attachPayroll`）把薪资合并回内存的 `staff[]`/`payrollRuns`，所以薪资页面的算法没改；存档时（`save`）再拆开，并由有权限的人算出一份只含总数的 `labourSum` 放在分店整包里，**区域副经理的「薪资总数」就读这份**。老数据由老板/人事经理第一次登录时自动迁移（先备份、确认云端写成功才剥离）。⚠️ 读取薪资失败（断网等）时 `PAY_LOADED` 不会设置：薪资页显示「没有载入」，绝不会把空数据写回去；`autoSyncLabour` 也因此不会把人工成本写成 0。⚠️ 员工自助「我的薪资单」目前暂停（员工读不到薪资，页面提示向人事索取 Payslip；原本也还没人填登入邮箱）。区域副经理在员工档案里改不到薪资/银行栏位（弹窗会隐藏）。
- **分店隔离（BUILD 1102mk69 起）**：数据库按角色限制能碰的 key——本店角色（店面经理/店长/厨师长/员工）只能读写自己那间的 `erpv2:<店>`；中央经理/员工只能碰 `erpv2:ck`；区域副经理 = `b1~b11`（不含 ck）；老板/人事经理 = 全部。网页用 `canWriteOutlet()`/`myOutlets()` 照同样规则**只载入自己能碰的分店**（读不到的绝不能当空数据去 seed）。`loadDB` 开头会 `clearSession()`（换人登录/退出时清空内存和本机缓存的薪资、调拨单，别让上一位的数据留在同一台手机）。因此原本「跨店写别人整包」的两处改了：① **订货表 `orderList` 搬到共用 key `erpv2:ckorder`**（`CKO`/`loadCkOrder`/`saveCkOrder`；所有白名单账号可读写；原因：店长/厨师长要填订货数量，以前是直接存进中央厨房整包，会连库存一起被旧数据覆盖）；读取失败时 `CKO_FAILED` 会禁止写入。② **跨店调拨改成「申请 → 对方批准」**（见下一条）。`erpv2:orders`、`erpv2:roleperms` 规则见 `store-lock.sql` 文件头。⚠️ **账号的「分店」栏位（`erp_users.outlet`）不能是空的/不对**：本店角色靠它决定能读哪间店，空的会被整个锁在外面。
- **跨店调拨申请（BUILD 1102mk70 起）**：「跨店调拨」页（`pgTransfer`）原本只是在自己店里记流水账（`d().transfers` 物品 / `d().staffLoans` 人力），对方店完全不知情。现在 `+物品申请`/`+借调申请`（`formXferNew`→`submitXferReq`）会送出一张申请，存成独立记录 `erpv2:req:<发起店>:<被申请店>:<编号>`（`XREQ`）：状态 `pending`（双方都显示「待批准 Pending」）→ 被申请店 `decideXreq` 批准/拒绝（拒绝可填原因，显示「被拒绝」）。**批准后**双方各自在 `applyApprovedFor(oid)` 把自己这一半记进整包：物品调出方 `invReduce`、调入方 `invReceive`，并各写一条 `transfers`/`staffLoans` 记录（带 `dir:'out'|'in'` 和 `reqId`，页面显示「→ / ←」+「✅已批准」，带 `reqId` 的行不能改不能删）；用 `xferApplied` 防重复；人力借调只记录，不移动员工档案。方向可选「向对方调入」或「调出给对方」。通知：顶栏 🔁 铃铛（`#xferBellBtn`，红点=待我批准的张数）、App 开着每 30 秒轮询（`startXferPoll`/`xferSync`）+ 登录时提示 + 响铃弹窗 + 申请结果（批准/拒绝）通知发起店；手机后台推送走 `sendXferPush`→`send-order-push`（带 `outlet`，只发给那间店的 outletmgr/manager/headchef/ckmgr 已「开启通知」的设备）——**Edge Function 要重新部署才会按店发送**（新版也让「新订单」推送只发给 owner/hrmgr/area）。谁能批准：`XFER_APPROVE_ROLES`（owner/hrmgr/area/outletmgr/manager/headchef/ckmgr），必须切到「被申请店」才能批准（`xferCanApprove`）；发起店可撤回 pending、移除 rejected（`withdrawXreq`）。数据库触发器 `erp_req_guard`（`store-lock.sql`）强制：新申请只能是 pending、只有被申请店（或 owner/hrmgr/area）能批准/拒绝、批准/拒绝后不能再改、只有发起店能删。⚠️ 旧的 `saveTransfer`/`erpv2:xfer:*` 调拨单机制（mk69）没人用，已删除。
- **推送函数 `send-order-push` 的安全（2026-11-02）**：Verify JWT 仍关，但函数自己验证——必须是已登录且在 `erp_users` 里 active 的账号（否则 401）；带 `outlet` 的调拨通知要有连着两间店的 `erpv2:req:*` 申请才发（admin 角色除外，否则 403）；标题/内容限长去 `<>`、图标固定 `icon-192.png`；每账号每分钟 20 次；CORS 只允许 `https://mengkeesystem.github.io`；`GET ?health=1` 只检查设定（VAPID 密钥、`erp_push_subs`/`erp_users` 连得上），绝不推送，回 `{ok:true}` 或 503 `{ok:false,problems:[…]}`，监控可以用。改完函数要业主在 Supabase 重新贴代码并 Deploy（不在 GitHub Pages 自动部署范围）。
- **界面（BUILD 1111mk73 起：旧界面已删除，三种主题）**：业主觉得旧界面「像小孩子」，参考 SUPY 流畅度 + Claude 设计风格。**只换外观，不改功能**；`<html class="ui2" data-theme="…">` 永远开着，没有开关了。三个主题由 `html.ui2[data-theme="classic|mech|cn"]` 的 CSS 变量决定（`<style id="ui2css">`）：**Default 默认 classic**（深酒红 `#7C1619` + 金 + 暖象牙，默认）、**机械风 mech**（mk75 起 Cyberpunk：近黑底 + 青/洋红霓虹网格、钢板卡片 + 四角螺丝 + 洋红硬阴影、LCD 霓虹数字、金属按钮、梯形山坡；浮在背景上的标题要用浅色）、**中式风 cn**（mk75 起新年气氛：红金顶栏 + 摇摆的红灯笼（`.top::before`）、铜钱底纹、「福」字印章标题、金线画框卡片、宋体；`.main` 顶部留了灯笼位；旧存的 `kampung` 会自动转成 `cn`）。每台设备各自记在 `localStorage.erpTheme`，切换在「系统设置 → 界面风格」（`setTheme()`，也会改手机状态栏色 `ui2ThemeColor`）。新增主题 = 加一组变量 + `UI2_THEMES` 一项 + 设置页一张卡。做了：① 表情符号统一换成线条图标（`UI2_EMOJI`→`UI2_ICON`，`MutationObserver` 统一处理；标题/按钮/折叠标题前不放图标）；② 手机顶栏一行（☰ + logo + 页面标题 + 分店 + ⋯，次要按钮收进 `#topMore`，`ui2LayoutTop`）；③ 手机底部导航 `#tabbar`（采购/进货/**总览（正中间，托在「小山坡」`#tabbar.hill::before` 上，`--hx` 定位）**/库存/调拨，按 `pageAllowed` 显示；不再有「更多」，左上角 ☰ 就是菜单；权限少的角色改显示 打卡/请假/薪资）：**当前页的那一颗浮起成主题色大圆圈（`button.on .ico`），不再固定在「进货」**；「进货」→ `goProcSub('purchase')`，图标暂用收件箱，**将来做「拍照识别发票」再换成相机**；调拨红点同步 `xferPendingForMe`；登录页不显示底栏。⚠️ 以后新加页面标题/按钮时**别在前面放表情符号**；Excel 风格格子（`.gtbl/.otbl/.pctbl`）只换颜色没动结构。**流畅度（mk74 已做）**：`render()` 同页重画保持滚动位置（含 `.gwrap/.card.tbl` 内部滚动）、换页才播进场动画（`.enter`）、登录载入数据时显示骨架屏（`skelHTML`）、表头固定（`.card.tbl` 最高 78vh 内部滚动）、关掉点按高亮、支持减少动画。**进货页（mk75 已做）**：`pgLedger` 供应商列表改成 今日/本月汇总 + 搜索 + 今日已录入置顶（绿色边）+ 编辑/删除收进「管理」。**mk76**：① 底部「小山坡」改成和圆钮严丝合缝的圆弧（SVG 路径，圆钮圆心正好在底栏上沿）；② 机械风：打开左侧菜单/点按钮有机械音效（WebAudio 现场合成，`sfx()`，不用音频文件）+ 菜单逐格弹出动画，修了深色底上看不清的字；③ 中式风：打开菜单/点按钮是烟花起飞声 + 火花（`fxBurst`），灯笼改成 3 个真的 DOM 元素（`#lanterns`，同一排可左右拖动，位置存 `localStorage.erpLant`，点一下放烟花）；④ Default：每次打开界面（或离开 5 分钟以上回来）一只小鱼蹦跳几下后淡出（`ui2Fish`）；⑤ 设置页「音效」开关（`localStorage.erpSfx`）；⑥ **进货「按日」视图**（`dayViewHTML`，`purchase` 专用，手机默认；右上「表格」可切回旧网格，偏好存 `localStorage.erpLedgerView`）：日期条 + 当天合计 + 品项行（数量/单价/鱼类还有重量，`dvCommit` 一行一起存，数量填好自动带上次单价）+ 搜索 + 排序（已录入优先/品名/金额）+「复制上一次」+ 底部本月合计。**mk77**：① 山坡与圆钮完全贴合（圆钮 70px、圆弧半径 34，SVG 路径里圆弧与圆钮同心，无光环/留白）；② 音效改版：机械风=机械键盘青轴 click-clack（`_key`），中式风=麻将拍桌/洗牌（`_mj`），Default=小鱼水花声（`_splashSnd`，开屏时手机没点过屏幕则不出声）；③ Default 开屏改成真实锦鲤（`FISH_SVG`）从水池跳出 3 次，rAF 抛物线 + 头尾随轨迹转向 + 水花/涟漪（`fishSplash`）+ 水花声，水池慢慢退去；④ **按日/卡片视图扩展到全部**：进货 `dayViewHTML`、月末盘点 `monthEndViewHTML`（单日=月末，单价自动中位数）、退货补货 `pgGRN`（按日分组卡片 + 退货/补货筛选 + 排序）、库存供应商内品项 `invCard`（低库存优先/品名/库存值）；电脑版同一风格（两栏）；进货/月末盘点右上「表格」可切回旧网格（`ledgerView` 默认 `day`）。**mk78**：① 总览圆钮改 `position:absolute`（圆心精确落在山坡圆弧圆心，之前是 flex 排版偏了 8px 才有缝）；② 音效只剩「一声」：机械风 click、中式风「啪」，开菜单也只是同一声，菜单直接出现无动画（mech/cn 的 `.side` 去掉 transition）；③ Default 开屏改成**鲤鱼跃龙门**（`ui2Fish`：水池 + 龙门 `GATE_SVG`，鲤鱼跳两下，第三跳在龙门中间变身金龙 `DRAGON_SVG`，盘旋升天淡出，约 6 秒；水花声 + 变身声 `sfx("dragon")`）；④ **手机表格自动变卡片**：`ui2Cardify()` 给表格格子补 `data-label`，窄屏 CSS 把一行变一张卡（跳过含输入框的表、`.gwrap/.gtbl/.odtbl`），员工档案/考勤/请假/菜品/开销等页一次性受益。**mk79/80**：① 龙门动画升级：龙改成 canvas 真龙 `drawDragon`（身体沿头的轨迹蜿蜒，鳞片/背刺/四爪/龙角/龙须/鬃毛/龙珠/云，从龙门里升起飞出屏幕），鱼放大、节奏加快（约 5 秒）；② 销售 `pgSales`、盘点 `pgStock`、应付账款 `pgAp` 改成 KPI + 搜索 + 筛选/排序 + 卡片（应付明细的 odtbl 也会在手机卡片化）。**mk81/82**：鱼跃龙门动画已关闭（`FISH_ON=false`，代码保留，要恢复改 true）；薪资发放 `pgPayrun` 加「按员工」卡片视图（`payView`，手机默认，电脑默认表格，两边共用同一组 `pi-*/po-*` id 所以 `payLiveRecalc` 不用改）；报表 `pgReport` 改成 概览/成本占比/盘点差异/损耗/呆滞货 五个标签；库存供应商列表也统一成 KPI+搜索+卡片；说明文字改成轻量灰字/折叠（`.hintd`）。下一步计划：逐页精修（月度核算、员工档案编辑弹窗、设置、中央厨房、BOM 等剩下的页面） → 进货单拍照识别（Anthropic API 密钥放 Supabase Secrets + 新 Edge Function）→ 新 POS API 对接（等选定）。
- 公司：明记有 11 间分店 + 中央厨房（`OUTLETS`：`ck`、`b1`~`b11`，b1 OKR、b2 PAPA、b3 PJ、b4 Cheras、b5 Kajang、b6 Puchong、b7 Subang、b8 Klang、b9 Bukit Rimau、b10 Setia Alam、b11 Seremban 2）。⚠️ **ERP 的 b2「PAPA店」和官网的「OKR (Scott Garden 对面)」、b3「PJ店」和官网的「Kelana Jaya (PJ)」应该是同一间店，但名字/顺序不一样**（官网分店序号是官网自己 `config.js` 的顺序，跟 ERP 的 `b1…b11` 没有对应关系）；以后要把官网订单接进 ERP 时要先问业主确认对照表。`OUTLETS` 里的经纬度是示意值，打卡 GPS 围栏用，不是精确位置。

### 怎么跟业主合作（很重要）
- **全部用中文回复**，白话、短句；先说结果再说细节。业主常给手机截图/录影，照图改（录影可以用 ffmpeg 逐帧拆开看）。
- 业主在**手机（iPhone）**上用，改动一定要考虑手机；Playwright 用 `/opt/pw-browsers/chromium`、`file://` 或本地 http server 测，视窗用 375×667 / 393×852（iPhone 15 Pro 真实尺寸）+ 桌面 1400×900。⚠️ headless Chromium **测不出 iOS 专属问题**（例如 `-webkit-overflow-scrolling`），业主实机说不行就要信他，不要只靠模拟测试说「已验证」。
- 流程：`git pull` → 改 `index.html` → 语法检查（抽出所有 `<script>` 跑 `node --check`）→ Playwright 测 → **bump `BUILD` + `sw.js` 的 `SW_VERSION`** → 提交（**中文提交信息**，结尾加系统给的 Co-Authored-By / Claude-Session 两行）→ `git push origin main`。
- 改了 `*.sql`：只推 GitHub 不会同步到数据库，要提醒业主去 Supabase SQL Editor 手动跑。
- 牛室那边先做、业主说「搬去明记」时：照牛室仓库 CLAUDE.md 里的「复制清单」，**保留明记自己的配置和数据**（见下面「搬功能时必须保留明记自己的」）。

### ⚠️ 这个仓库有「两个会话同时在推 main」
**牛室那边的 Claude 会话也有权限直接推这个仓库的 `main`**（功能经常同步），不会提前打招呼：`git log` 可能看到不是你推的 commit；不先 `git fetch` 比对就推，可能用旧的 BUILD 号覆盖/冲突。
1. 每次改 `index.html`/`sw.js` 前先 `git fetch origin main`，远端比本地新就先看远端改了什么（尤其 `BUILD`/`SW_VERSION`）再合并，不要盲目覆盖。
2. `BUILD` 和 `SW_VERSION` 必须**同步手动升级**（格式 `MMDDmkNN`，例如 `1111mk72`），推送前确认两边一致、且比远端当前值大。
3. 如果被分配了任务分支，要知道 GitHub Pages 只认 `main`；历史上本项目一直是直接 `git push origin main`，没有走 PR，没出过问题。新会话如被分配不同分支，先跟业主确认部署策略。
4. 看到自己没做过的 commit，大概率是牛室会话推的（例如提示音），先 `git log` 看内容，别当成 bug。

### 推送前检查清单（单文件，手滑漏一个括号整站白屏）
```bash
git fetch origin main
node --check sw.js
node -e "const fs=require('fs');const html=fs.readFileSync('index.html','utf8');let n=0;for(const m of html.matchAll(/<script>([\\s\\S]*?)<\\/script>/g)){new Function(m[1]);n++}console.log('INLINE_SCRIPTS_OK',n)"
```
然后 `BUILD` + `SW_VERSION` 一起 +1 → 中文提交信息写清楚改了什么、为什么 → `git push origin main`。影响界面/权限/数据结构的改动，请业主看截图/录屏确认。

### 线上 Supabase 要跑过哪些 SQL（业主手动跑）
1. `supabase-schema.sql`：`erp_store`、`erp_users`（岗位/分店/active）+ 第一版权限。
2. **`security-hardening.sql`（正式上线前必跑）**：把权限判断搬到 RLS——`my_email()`/`is_whitelisted()`/`is_admin()`/`erp_users_is_empty()`/`invite_role()`/`invite_outlet()` + `erp_users` 与 `erp_store`/`erp_push_subs`/`receipts` 储存桶的策略（只有白名单里 active 的账号能读写）。全部 plpgsql（不要写成 `language sql`，会触发 RLS 无限递归 42P17——牛室踩过的坑）。
3. `push-schema.sql`：`erp_push_subs`（手机推送订阅）——**业主已跑过**（一开始没建表导致「开启通知」一直失败）。`PUSH_SETUP_MENGKEE.md` 是推送设定步骤；Edge Function `send-order-push` **业主已在 Supabase 网页控制台手动部署**（Secrets 先设 `VAPID_PUBLIC`/`VAPID_PRIVATE`/`VAPID_SUBJECT`，再贴代码，并**关掉「Verify JWT」**——没部署/没关就是浏览器 F12 CORS 报错的根因，不是代码问题，也不影响下单）。
4. `STORAGE_SETUP_MENGKEE.md`：付款收据储存桶 `receipts`（私人，白名单可读写）。
5. Supabase 后台手动：Authentication → Providers → Email → **打开「Confirm email」**（SQL 做不到）。
6. **`store-lock.sql`（BUILD 1102mk69 起要跑；取代之前的 `payroll-lock.sql`，已删除）**：按角色/分店给 `erp_store` 每个 key 上锁（函数 `erp_key_ok` + 策略 `erp_store key-locked`）。跑之前：先让老板/人事经理用新版登录一次（自动把订货表搬出中央厨房整包），再跑文件里「跑之前先检查」那条查询（应为 0 行）。可重复运行，文件末尾有还原语句。**mk70 起它还包含调拨申请的触发器 `erp_req_guard`，所以升级到 mk70 后要再跑一次。**
- 邀请码机制（2026-11-02 BUILD 1102mk69 起改版）：**码不再写在网页/仓库里**，存在 Supabase 私有表 `erp_invite_codes`（`code`/`role`/`outlet`，开 RLS 且无策略，网页读不到整张表）。网页注册时调用 `rpc('invite_info')`（`inviteLookup()`）查 {role,outlet}；数据库的 `erp_users` 插入策略用 `invite_role()`/`invite_outlet()`（`security-hardening.sql` 第 1 部分，security definer）核对。**换码 = 在 SQL Editor 对 `erp_invite_codes` 做 delete + insert，不用改代码、不用推送**。每个码是 10 位随机字符，一码一用途：区域副经理/中央经理/中央员工各 1 个，11 间分店各 4 个（店面经理 `outletmgr`/店长 `manager`/厨师长 `headchef`/员工 `staff`）。**码本身绝不写进仓库/文档**，完整清单由业主自己保管（需要时可重新生成一批并给业主 SQL）。`NO_CODE_EMAIL`（`index.html` 约 640 行）= 业主本人的救援邮箱，注册免邀请码、直接给老板角色；`security-hardening.sql` 里也有同样的邮箱，两边要对得上。
- 登录：邮箱+密码（Supabase Auth）；已有「忘记密码」（寄重设链接 → `PASSWORD_RECOVERY` → 设新密码页 → 改完回登录页）；Supabase 后台 Authentication → URL Configuration 的 Redirect URLs 要包含 ERP 的网址。

### 角色和权限（`ROLES`，`index.html` 约 579 行；⚠️ 角色代号跟牛室不一样）
| 代号 | 名称 | 范围 | 能进的模块（`can`） | 薪资 |
|---|---|---|---|---|
| `owner` | 老板 | 全分店 | 全部（含财务、设置） | 看全部个人明细；**薪资发放锁死只读**（`salaryLock`） |
| `hrmgr` | 人事经理 | 全分店 | 权限同老板 | **唯一能实际处理「薪资发放」的角色**；后台手动分配，不走邀请码 |
| `area` | 区域副经理 | 全分店（不含中央厨房） | 同老板但没有 `ck`/中央厨房、薪资只看**总数** | 发放锁死只读 |
| `outletmgr` | 店面经理（Outlet P.I.C） | 本店 | 看板/库存/采购/盘点/损耗/招待/BOM/开销/报表/AP/人事自助 | 看本店每位员工薪水，锁死只读 |
| `manager` | 店长 | 本店 | 看板/库存/采购/盘点/损耗/开销/报表/AP | 只看自己 |
| `headchef` | 厨师长 | 本店 | 看板/库存/调拨/盘点/AP（可核对更改应付，不能删） | 只看自己 |
| `staff` | 员工 | 本店 | 打卡/请假/自己的薪资（人事自助） | 只看自己 |
| `ckmgr` / `ckstaff` | 中央经理 / 中央员工 | 锁定中央厨房 `ck` | 见 `ROLES`（`ckOnly:true`） | 只看自己 |
- ⚠️ **跟牛室的对照**：牛室的 `hrmanager` = 明记的 `hrmgr`；牛室的 `manager`（店面经理）≈ 明记的 `outletmgr`；牛室的 `canRunPayroll()` 在明记对应 `salaryLock` 这套。**从牛室搬代码时角色名要逐个换，不能直接复制**。
- 权限可在「设置→岗位权限编辑」改（存 `erpv2:roleperms`）。`canEditPerms`：老板/人事经理/区域副经理。管理员可用「岗位预览」假装别的角色看界面，真实身份用 `curUser.role`。
- **闲置自动登出**（`IDLE_ROLES` = `manager`/`headchef`/`staff`/`ckmgr`/`ckstaff`，**精确这 5 个**，其余角色不受限）：闲置满 29 分钟先跳「继续使用」倒数 60 秒，再无操作满 30 分钟强制登出；弹窗表单开着时不计闲置。
- **`currentEmpId()`**（2026-09-30 已修，别再写死）：按登录邮箱去员工档案 `staff[].email` 找人；找不到回 `null`（员工自助看不到资料，不会看错人）。员工第一次用自助功能前，人事要先在员工档案填好他的登录邮箱（已加「同一邮箱不能绑第二位员工」的拦截）。

### 页面（侧栏 `MENU`）和功能
- **营运**（⚠️ 采购进销里的「跨店调拨」现在是申请制，见上）：利润大盘 `dash`、销售(POS) `sales`、采购进销 `proc`（作业中心：订货单/进货单/退货补货/报废损耗/招待赠送/跨店调拨/运营开销记录…，**六项都按月份分开**）、订单发票 `orderinv`、中央厨房 `ck`（含订货表，用含图片版）。
- **库存**：库存 `inv`、配方成本 `bom`（BOM；`DISH_CATALOG` 内置菜品成本表）、**盘点 `stock`（明记主用，配合 BOM 抓理论 vs 实盘盘差）**、月末盘点 `monthend`、运营开销录入 `opexm`。
- **财务**：应付账款 `ap`（逐项✔/✗核对订单 + 开票收付 + 对账）、运营开销 `opex`、月度核算 `monthly`、报表 `report`。
- **人事**：员工档案 `hr`、考勤 `attend`（GPS 打卡）、排班 `schedule`、请假 `leave`、人事薪资 `payroll`、薪资发放 `payrun`（马来西亚法定公式 EPF/SOCSO/EIS/SL24J/PCB + OT + 公共假期津贴；Payslip；已有 CP39 / Borang A / 8A / 银行代发文件 / EA 表导出）。
- **系统**：设置&审计 `settings`（账号权限、员工操作监察 `auditLog`、版本更新面板、手动检查更新）。
- 成本核算三种方式（`costCfg()`，**默认 ② 成本算货**）：① 成本率法　② 进销存实耗法/成本算货（月初库存 + 进货 − 月末库存）　③ 配方法（BOM × 销量）。明记定位：**主力单点/煮炒菜做 BOM + 盘点；杂饭/小菜走月度核算兜底**（牛室相反：整体看月度核算，单点才做 BOM）。
- **推送平台限制（不是 bug，已跟业主解释过）**：iOS 一定要「加到主屏幕」变成已安装的 PWA 才收得到关掉 App 后的后台推送，单开 Safari 分页收不到；iOS 通知声音要去 系统设置→通知→这个 App→手动开「声音」；声音开了还不响先查专注/勿扰模式和系统提示音量（业主说先不理，搁置）。
- 手机推送（新订单通知）：`VAPID_PUBLIC`/`PUSH_FN_URL`/`sendOrderPush`；老板/人事经理/区域副经理收「新订单」🔔（Note 风格两声铃）；**所有账号**收「版本更新」小铃铛（Tri-tone 风格三声，`playUpdateChime`）。
- 版本更新机制（mk72 加固）：`startUpdateCheck()` 在 SW 注册后马上启动，**不等登录/载入数据流程**（那一步万一卡住也照样检查；要用 `setTimeout(...,0)` 等整个脚本载入完再调，否则会碰到还没定义的 `let` 变量）；`checkForUpdate` 的 fetch 有 15 秒超时（`AbortController`），上一次检查卡住超过 30 秒会被丢弃（以前卡住会让 `_updChecking` 永远为 true，之后所有检查都被跳过，只能完全关掉 App 重开）；`isBusyEditing` 不把顶栏里的分店/岗位选单算成「在填表」（选完它们会一直保持焦点，会把强制更新窗无限期推迟）。
- 版本更新机制：`checkForUpdate()` 每 5 分钟 + 回前台时抓服务器 `index.html` 比对 `BUILD`；有新版就跳**强制更新弹窗**（只有「确认更新」，ESC 关不掉）；**表单弹窗开着/光标在输入框里时延后弹**（`tryShowForcedUpdate`、`isBusyEditing`），避免冲掉正在填的资料。`sw.js` 网络优先 + 缓存名带版本号。

### 明记 vs 牛室：已经对齐的（2026-09 同步过来的）
明记 2026-09-15 一次性同步牛室的新功能（保留明记数据/配置/招牌/菜单），之后跟着对齐：邀请码按分店发码、人事经理、中央经理/员工、忘记密码、手机版操作优化（按钮大小/安全区/侧栏滚动锁）、PWA 自动更新 + 强制更新弹窗 + 版本铃铛 + 提示音、闲置自动登出、XSS 转义补洞、薪资发放（年份→月份 tab、月份可删需两次确认）、运营开销记录（逐笔）自动同步运营开销、报废/招待下拉选单、ESC 关弹窗、SQL Payroll 对接（CP39/Borang A/8A/银行文件/EA 表/公共假期/Payslip 隐藏 OT 倍数，BUILD 0930mk62）、`currentEmpId` 修复。

### 明记自己的做法 / 跟牛室不一样的地方（搬功能时别覆盖）
- **供应商/品项**：`SUPPLIER_CATALOG`（来自明记 OKR 的进货记录，`index.html` 约 332 行起）和 `order-data.js`（订货单，中央厨房含图片）是明记的；Supabase 里存过的供应商会覆盖种子。「库存」页有「导入供应商全部品项」「用月均价重算成本」；订货单有「统一品名+补图片」。
- **进货单逐日记价**：明记自己做过「数量/当天价钱/总数」（松/马友/龙虎斑这类鱼供应商是「重量×价钱」）；**月末盘点单价 = 当月每日进货单价的「中位数」**（牛室用加权平均，**两边不一样**）。
- **运营开销记录同步**：明记是「显示层汇总」（`opexLogMonthTotals`，`OPEXLOG_CATS`），牛室是写回 `curOpex`；效果相同，但函数名不同。
- 退货/补货是「供应商 → 月份 → 逐笔表单」；招待赠送跟随明记 ENT/Offer 表；报废损耗跟随明记损耗记录表。
- 登录页/页头/图标用明记红色 logo；`appTitle` = 明记家乡小食店 / Meng Kee Eatery。
- 区域副经理**看不到**中央厨房（`allBranch:true` 但 `can` 没有 `ck`）；中央厨房订货由老板/人事经理/中央角色处理。

### 牛室有、明记**还没有**的功能（业主说要搬时再做；逐项先问业主、按明记角色名调整）
1. **会计总账整套**（复式记账、科目表 SQL Account 编号、试算表/损益/资产负债/现金流量、固定资产折旧、PV/OR/JV 单据号、应收应付账龄、银行对账、SST 报表、销售结账、进货自动过账）——大工程，明记收入科目不同（没有自助餐，是煮炒/饭/饮料）；`canEditAccounting`（只有人事经理能改，老板/区域副经理只读）。
2. 租金/水电煤气自动过账 + 月度 COGS 过账（依赖第 1 项）。
3. `SUPREME_OWNER_EMAIL` 系统最高权限账号保护（别的老板/人事经理/区域副经理动不了最高权限账号和老板账号）。
4. **按分店隔离的 RLS + 薪资单独上锁**（⚠️ 明记已在 BUILD 1102mk68/69 自己做完，做法见上，不用搬）：牛室的 `erp_store` 只让「本店 / 全分店角色」读写自己的 key，薪资发放结果拆成 `erpv2:payroll:<店>` 只有老板/人事经理能读；订货单 `erpv2:orders` 单独开放。**明记目前是「白名单里任何账号能读写 erp_store 全部 key」**（见「安全待办」）。
5. 手机版进货单/月末盘点表格的修复（牛室 2026-10-02，BUILD 1002b–j）：iPhone 15 Pro 上表格左右滑不动，真根因是钉住的 Code/品名/单位/规格 4 栏加起来 430px > 屏幕 393px；改成只钉「品名」一栏（宽 92px）+ JS 触摸接管 + ◀▶ 备用按钮 + 拿掉 `-webkit-overflow-scrolling:touch`。**明记没有对照检查过，业主的 iPhone 上很可能有同样问题，先让业主实测再决定要不要搬。**
6. 强制更新弹窗图标换成蓝色圆角方块 SVG（BUILD 0930i，明记那边应已一致，未核对）。
7. `canRunPayroll` 式的更细薪资权限、`pageAllowed('payrun')` 的收紧——明记已有 `salaryLock` 做同样的事，不必搬。

### ⚠️ 安全待办（2026-11-02 复查发现，**业主还没处理**）
1. ✅ **已处理（BUILD 1102mk69）**：已换新 VAPID 密钥对，仓库里只剩公钥；新私钥只在业主手上/Supabase Secrets（业主需手动更新 Secret 并让大家重新「开启通知」，见下）。原问题：`PUSH_SETUP_MENGKEE.md` 把 `VAPID_PRIVATE`（手机推送的私钥）明文写在公开仓库里**（牛室的 `PUSH_SETUP.md` 同样）。要**换一组新的 VAPID 密钥**：生成新密钥对 → 新私钥只放 Supabase Function Secrets → 新公钥更新 `index.html` 的 `VAPID_PUBLIC` → 把文档里的私钥删掉 → 所有人重新点「开启通知」。（git 历史里旧私钥洗不掉，所以必须换。）
2. ✅ **已处理（BUILD 1102mk69）**：邀请码改成存数据库私有表、随机新码，仓库里不再有任何码。旧码已作废（旧码仍在 git 历史里，但数据库不认了）。业主需在 SQL Editor 执行换码 SQL（见上「邀请码机制」）。
3. 记得确认 Supabase 的「Confirm email」是开着的。
4. ✅ **已处理（BUILD 1102mk69）**：薪资已拆出去上锁，分店之间也按角色隔离（见上「薪资数据单独存放」「分店隔离」；业主要跑 `store-lock.sql`）。仍有的限制：同一间店的所有角色共用一个整包（店长/厨师长/员工之间没有再细分）；`erpv2:orders` 所有白名单账号可读写。

### 搬功能时「必须保留明记自己的」（逐行核对，别照抄牛室）
1. `SUPABASE_URL`（约 746 行，`https://kmcdokwiyetlmsrdlgqw.supabase.co`）= 明记项目；`SUPABASE_ANON_KEY` = 明记的 publishable key；**绝不能出现牛室的项目网址/key**。只放 publishable key，**绝不放 service_role**。
2. `VAPID_PUBLIC` / `PUSH_FN_URL` / `RECEIPT_BUCKET`（约 752–755 行）。
3. `appTitle`（约 653 行）、页头 logo、图标、`apple-touch-icon`。
4. `SUPPLIER_CATALOG`、`OUTLETS`（`ck` + `b1`~`b11`）、邀请码表 `erp_invite_codes`/`inviteLookup()`（⚠️ 牛室若还是把码写在网页里，别照搬过来）、`NO_CODE_EMAIL`。
5. `ROLES` 的角色代号和权限清单（`hrmgr`/`outletmgr`/`ckmgr`/`ckstaff`…）。
6. `IDLE_ROLES` 的 5 个角色。
7. `sw.js`：`SW_VERSION`、`CACHE_NAME = 'mengkee-erp-' + SW_VERSION`、`CORE_ASSETS`；改了 `index.html` 的 `BUILD` 一定同步。
8. 盘点（`stock`）要留在侧栏「库存」组（明记主用逐品项盘点）。

### 官网和 ERP 共用同一个 Supabase 项目时的规矩
- 官网用 `web_*` 开头的表/函数（`web_orders`、`web_staff`、`web_outlets`、`web_menu_86`、`web_order_proofs`、`web_refunds`…）和 Edge Functions `web-hitpay`/`web-delyva`；ERP 用 `erp_*`、`my_email`/`is_whitelisted`/`is_admin`/`invite_*`、`send-order-push`。**名字不冲突，互相不改对方的表/策略**。
- 官网店员用自己的 ERP 登录账号登录官网后台，但还要被加进官网的 `web_staff` 才看得到订单（ERP 白名单 ≠ 官网店员白名单）。
- 在 SQL Editor 跑任何 SQL 前，先确认没有 `drop ... cascade` 会碰到 `web_*`。

### 测试
Playwright 无头测试（`file://` 打开 `index.html`，或 `python3 -m http.server 8765` 同一条命令里启动再测）：登录流程、侧栏、各页面切换、弹窗、进货单网格、薪资计算（`computeRow`）、`currentEmpId`、闲置登出（改 `_lastActivity` 模拟）、强制更新弹窗（`showUpdateBanner`）。没有自动化测试脚本放在仓库里，每次现写。

### 历史重点（时间顺序，新的在后；细节看 git log 对应 commit）
1. 多分店进销存基础框架、库存成本核算、配方成本、六大作业拆分独立页面；Supabase 真实登录 + 白名单 + RBAC。
2. 运营开销(OpEx)按自然月独立核算，联动人事薪资自动算人工成本；月末盘点单价 = 当月每日进货单价的**中位数**（不是平均数）。
3. 人事经理 `hrmgr` 新角色（权限同老板，独占「处理薪资发放」）；老板/区域副经理的薪资发放锁死只读（`salaryLock:true`）；XSS 转义全站补齐（`oEsc`）；员工档案编辑权限收紧到区域副经理以上（`hrEditable()`）。
4. 薪资发放页年份分组 + 手动新增月份 + 删除月份（连续两次确认）。
5. 忘记密码（`resetPasswordForEmail`/`updateUser`），修过两次竞态（重设密码页被正常登录流程抢回主系统）。
6. 手机端：App 图标改成正确的「明记」图标（`icon-192/512.png`、`apple-touch-icon.png`）；侧栏滑动穿透背景、滑到底弹回、顶栏换行盖住按钮等，都是看业主真机录屏（ffmpeg 抽帧）找出根因逐个修的（`--topH`、`overscroll-behavior:contain`、`100dvh`、`touch-action`…），**不要凭空猜**。
7. 报废/招待品项改成纯 `<select>`（跟跨店调拨一致）；ESC 关弹窗。顶栏「分店名」和「版本号」位置互换，**连样式也要互换**（业主纠正过两次，见 commit `d96095d`/`113ebcb`/`3d3437a`）。
8. 自动版本更新（`checkForUpdate` 轮询 + SW `updatefound`）+ 强制更新弹窗 + 全员更新铃铛（`#updBellBtn`，`icon-update.png`）+ `sw.js` 网络优先缓存。
9. 闲置自动登出、提示音（Note/Tri-tone，**是牛室会话直接推过来的，明记原样沿用**）。
10. 推送通知修复（见上「SQL」第 3 项）。
11. `currentEmpId()` 写死返回 1 的 bug 修复（见上）；员工档案新增「登入邮箱」`em_email` + 重复绑定拦截。**待办**：现有员工档案都还没填登入邮箱——哪天要开放 `manager`/`headchef`/`staff`/`ckmgr`/`ckstaff` 自己登录用「自助查看」前，人事（hrmgr/area/owner）要先在「人事 → 员工档案」补每位员工的登入邮箱，否则他们会看到「账号尚未绑定员工档案」（刻意的安全设计：宁可看不到，也不要看错人）。

### 待确认 / 没做完
- **11 家分店名字对不对得上实际分店**：业主曾提到「Setapak店」（那是牛室的店），ERP 里没有；问过业主这 11 家是否对得上，**业主一直没回复，别主动再追问，等业主自己提起**。要加第 12 家分店时要在 `erp_invite_codes` 表里补那间店的 4 个码。
- 业主说过会上传一份人工算好的 BOM/配方成本文件来导入，一直没上传，不用主动跟进。
- 业主有没有把 `security-hardening.sql`、收据储存桶 `receipts` 都跑过、Supabase「Confirm email」是否打开——没有书面确认。
- 上面「安全待办」两项（VAPID 私钥外泄要换；邀请码在公开仓库）。
- 牛室有的功能要不要搬（尤其会计总账、按分店隔离 RLS、手机版进货单修复）。
- ERP 分店 `b1…b11` 和官网分店的对照表（接官网订单进 ERP 时才需要）。
- 完整邀请码列表 Excel 曾整理给业主，没有存在仓库里（需要时重新生成）。
