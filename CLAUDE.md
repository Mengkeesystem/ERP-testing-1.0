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
- **当前版本：`BUILD="1102mk66"`**（`index.html` 约 668 行），`sw.js` 的 `SW_VERSION` 要**同步改成一样**（每次改动两处一起 +1，右上角版本角标和强制更新弹窗靠它）。版本号格式 `MMDDmkNN`（mk = 明记）。最后一次提交 2026-09-30。
- 部署：GitHub Pages，**直接推 `main` 就上线**（不开分支、不开 PR），网址 `https://mengkeesystem.github.io/ERP-testing-1.0/`。业主要求跟牛室一样：改完测完直接推。
- 后端 Supabase 项目网址 `https://kmcdokwiyetlmsrdlgqw.supabase.co`；`SUPABASE_ANON_KEY` 是 publishable key（前端公开的，没问题）。**私钥类（service_role、VAPID 私钥）绝对不写进代码/文档**，只放 Supabase Secrets。
- 数据存哪：登录后用 Supabase（`Store.get/set` → `erp_store` 表，key 是 `erpv2:<分店id>`、`erpv2:roleperms`、`erpv2:orders`）；没登录（演示模式）用浏览器本机。代码改了**不会动到数据**（数据在 Supabase，不在 `index.html` 里）。
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
2. `BUILD` 和 `SW_VERSION` 必须**同步手动升级**（格式 `MMDDmkNN`，例如 `1102mk66`），推送前确认两边一致、且比远端当前值大。
3. 如果被分配了任务分支，要知道 GitHub Pages 只认 `main`；历史上本项目一直是直接 `git push origin main`，没有走 PR，没出过问题。新会话如被分配不同分支，先跟业主确认部署策略。
4. 看到自己没做过的 commit，大概率是牛室会话推的（例如提示音），先 `git log` 看内容，别当成 bug。

### 推送前检查清单（单文件，手滑漏一个括号整站白屏）
```bash
git fetch origin main
node --check sw.js
node -e "const fs=require('fs');const html=fs.readFileSync('index.html','utf8');const m=html.match(/<script>([\\s\\S]*)<\\/script>\\s*<\\/body>/);new Function(m[1]);console.log('INLINE_SCRIPT_OK');"
```
然后 `BUILD` + `SW_VERSION` 一起 +1 → 中文提交信息写清楚改了什么、为什么 → `git push origin main`。影响界面/权限/数据结构的改动，请业主看截图/录屏确认。

### 线上 Supabase 要跑过哪些 SQL（业主手动跑）
1. `supabase-schema.sql`：`erp_store`、`erp_users`（岗位/分店/active）+ 第一版权限。
2. **`security-hardening.sql`（正式上线前必跑）**：把权限判断搬到 RLS——`my_email()`/`is_whitelisted()`/`is_admin()`/`erp_users_is_empty()`/`invite_role()`/`invite_outlet()` + `erp_users` 与 `erp_store`/`erp_push_subs`/`receipts` 储存桶的策略（只有白名单里 active 的账号能读写）。全部 plpgsql（不要写成 `language sql`，会触发 RLS 无限递归 42P17——牛室踩过的坑）。
3. `push-schema.sql`：`erp_push_subs`（手机推送订阅）——**业主已跑过**（一开始没建表导致「开启通知」一直失败）。`PUSH_SETUP_MENGKEE.md` 是推送设定步骤；Edge Function `send-order-push` **业主已在 Supabase 网页控制台手动部署**（Secrets 先设 `VAPID_PUBLIC`/`VAPID_PRIVATE`/`VAPID_SUBJECT`，再贴代码，并**关掉「Verify JWT」**——没部署/没关就是浏览器 F12 CORS 报错的根因，不是代码问题，也不影响下单）。
4. `STORAGE_SETUP_MENGKEE.md`：付款收据储存桶 `receipts`（私人，白名单可读写）。
5. Supabase 后台手动：Authentication → Providers → Email → **打开「Confirm email」**（SQL 做不到）。
- 邀请码机制：**网页**（`index.html` 的 `INVITE_CODES`）和**数据库**（`security-hardening.sql` 的 `invite_role`/`invite_outlet`）各有一份对照表，**要同步改**。格式：区域副经理/中央经理/中央员工各一个固定码；店面经理/经理/厨师长/员工每间分店各一组（`b1`~`b11` + 职位码）。**不要把码写进文档**。`NO_CODE_EMAIL`（`index.html` 约 648 行）= 业主本人的救援邮箱，注册免邀请码、直接给老板角色；`security-hardening.sql` 里也有同样的邮箱，两边要对得上。
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
- **营运**：利润大盘 `dash`、销售(POS) `sales`、采购进销 `proc`（作业中心：订货单/进货单/退货补货/报废损耗/招待赠送/跨店调拨/运营开销记录…，**六项都按月份分开**）、订单发票 `orderinv`、中央厨房 `ck`（含订货表，用含图片版）。
- **库存**：库存 `inv`、配方成本 `bom`（BOM；`DISH_CATALOG` 内置菜品成本表）、**盘点 `stock`（明记主用，配合 BOM 抓理论 vs 实盘盘差）**、月末盘点 `monthend`、运营开销录入 `opexm`。
- **财务**：应付账款 `ap`（逐项✔/✗核对订单 + 开票收付 + 对账）、运营开销 `opex`、月度核算 `monthly`、报表 `report`。
- **人事**：员工档案 `hr`、考勤 `attend`（GPS 打卡）、排班 `schedule`、请假 `leave`、人事薪资 `payroll`、薪资发放 `payrun`（马来西亚法定公式 EPF/SOCSO/EIS/SL24J/PCB + OT + 公共假期津贴；Payslip；已有 CP39 / Borang A / 8A / 银行代发文件 / EA 表导出）。
- **系统**：设置&审计 `settings`（账号权限、员工操作监察 `auditLog`、版本更新面板、手动检查更新）。
- 成本核算三种方式（`costCfg()`，**默认 ② 成本算货**）：① 成本率法　② 进销存实耗法/成本算货（月初库存 + 进货 − 月末库存）　③ 配方法（BOM × 销量）。明记定位：**主力单点/煮炒菜做 BOM + 盘点；杂饭/小菜走月度核算兜底**（牛室相反：整体看月度核算，单点才做 BOM）。
- **推送平台限制（不是 bug，已跟业主解释过）**：iOS 一定要「加到主屏幕」变成已安装的 PWA 才收得到关掉 App 后的后台推送，单开 Safari 分页收不到；iOS 通知声音要去 系统设置→通知→这个 App→手动开「声音」；声音开了还不响先查专注/勿扰模式和系统提示音量（业主说先不理，搁置）。
- 手机推送（新订单通知）：`VAPID_PUBLIC`/`PUSH_FN_URL`/`sendOrderPush`；老板/人事经理/区域副经理收「新订单」🔔（Note 风格两声铃）；**所有账号**收「版本更新」小铃铛（Tri-tone 风格三声，`playUpdateChime`）。
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
4. **按分店隔离的 RLS + 薪资单独上锁**：牛室的 `erp_store` 只让「本店 / 全分店角色」读写自己的 key，薪资发放结果拆成 `erpv2:payroll:<店>` 只有老板/人事经理能读；订货单 `erpv2:orders` 单独开放。**明记目前是「白名单里任何账号能读写 erp_store 全部 key」**（见「安全待办」）。
5. 手机版进货单/月末盘点表格的修复（牛室 2026-10-02，BUILD 1002b–j）：iPhone 15 Pro 上表格左右滑不动，真根因是钉住的 Code/品名/单位/规格 4 栏加起来 430px > 屏幕 393px；改成只钉「品名」一栏（宽 92px）+ JS 触摸接管 + ◀▶ 备用按钮 + 拿掉 `-webkit-overflow-scrolling:touch`。**明记没有对照检查过，业主的 iPhone 上很可能有同样问题，先让业主实测再决定要不要搬。**
6. 强制更新弹窗图标换成蓝色圆角方块 SVG（BUILD 0930i，明记那边应已一致，未核对）。
7. `canRunPayroll` 式的更细薪资权限、`pageAllowed('payrun')` 的收紧——明记已有 `salaryLock` 做同样的事，不必搬。

### ⚠️ 安全待办（2026-11-02 复查发现，**业主还没处理**）
1. ✅ **已处理（BUILD 1102mk66）**：已换新 VAPID 密钥对，仓库里只剩公钥；新私钥只在业主手上/Supabase Secrets（业主需手动更新 Secret 并让大家重新「开启通知」，见下）。原问题：`PUSH_SETUP_MENGKEE.md` 把 `VAPID_PRIVATE`（手机推送的私钥）明文写在公开仓库里**（牛室的 `PUSH_SETUP.md` 同样）。要**换一组新的 VAPID 密钥**：生成新密钥对 → 新私钥只放 Supabase Function Secrets → 新公钥更新 `index.html` 的 `VAPID_PUBLIC` → 把文档里的私钥删掉 → 所有人重新点「开启通知」。（git 历史里旧私钥洗不掉，所以必须换。）
2. **邀请码在公开仓库里**（`security-hardening.sql`、`index.html` 的 `INVITE_CODES`；牛室的 CLAUDE.md 里甚至整张列出来）。知道码的人可以自己注册成对应分店的店面经理/店长。选项：① 把 ERP 仓库改成私有（GitHub Pages 私有仓库要付费方案）；② 换一批新码，并把码从仓库里拿掉（只放 Supabase 环境，或由老板手动在后台加白名单）。**换码时网页和数据库两处要同步**。
3. 记得确认 Supabase 的「Confirm email」是开着的。
4. 明记的 `erp_store` 没有按分店隔离、薪资没有单独上锁（见上面第 4 项），懂技术的员工账号理论上能用浏览器直接读到别店/薪资数据。

### 搬功能时「必须保留明记自己的」（逐行核对，别照抄牛室）
1. `SUPABASE_URL`（约 746 行，`https://kmcdokwiyetlmsrdlgqw.supabase.co`）= 明记项目；`SUPABASE_ANON_KEY` = 明记的 publishable key；**绝不能出现牛室的项目网址/key**。只放 publishable key，**绝不放 service_role**。
2. `VAPID_PUBLIC` / `PUSH_FN_URL` / `RECEIPT_BUCKET`（约 752–755 行）。
3. `appTitle`（约 653 行）、页头 logo、图标、`apple-touch-icon`。
4. `SUPPLIER_CATALOG`、`OUTLETS`（`ck` + `b1`~`b11`）、`INVITE_CODES`（明记的码和格式）、`NO_CODE_EMAIL`。
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
- **11 家分店名字对不对得上实际分店**：业主曾提到「Setapak店」（那是牛室的店），ERP 里没有；问过业主这 11 家是否对得上，**业主一直没回复，别主动再追问，等业主自己提起**。要加第 12 家分店时要同步改邀请码（网页 + 数据库两处）。
- 业主说过会上传一份人工算好的 BOM/配方成本文件来导入，一直没上传，不用主动跟进。
- 业主有没有把 `security-hardening.sql`、收据储存桶 `receipts` 都跑过、Supabase「Confirm email」是否打开——没有书面确认。
- 上面「安全待办」两项（VAPID 私钥外泄要换；邀请码在公开仓库）。
- 牛室有的功能要不要搬（尤其会计总账、按分店隔离 RLS、手机版进货单修复）。
- ERP 分店 `b1…b11` 和官网分店的对照表（接官网订单进 ERP 时才需要）。
- 完整邀请码列表 Excel 曾整理给业主，没有存在仓库里（需要时重新生成）。
