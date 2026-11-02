# 明记ERP · 交接总览（2026-11-02 整理，供换账号/新会话接手用）

> 这份文件是给**接手这个项目的新 Claude 会话**看的。新会话一进来应该先读完这份文件，
> 再去看代码，避免重复踩坑或遗漏之前已经修好/讨论过的点。

## 项目是什么

- 单文件 vanilla JS 多分店餐饮 ERP（`index.html`，一个文件包含全部前端逻辑），给
  **"明记家乡小食店"**（马来西亚多分店小食连锁）用。
- 托管：GitHub Pages，从 `main` 分支部署，网址
  `https://mengkeesystem.github.io/ERP-testing-1.0/`。
- 仓库：`Mengkeesystem/ERP-testing-1.0`。
- 后端：Supabase（Postgres + Auth + Storage + Edge Functions）。
  - Project URL: `https://kmcdokwiyetlmsrdlgqw.supabase.co`
  - publishable key 已写在 `index.html` 里（`SUPABASE_ANON_KEY`，前端公开的，没问题）
  - **私钥类的东西（VAPID_PRIVATE、service role key）绝对不写进代码**，只能放
    Supabase 自己的 Secrets/环境变量里。
- 老板本人（这个项目的甲方）邮箱：`youjuanchong@gmail.com`。
- PWA：`manifest.webmanifest` + `sw.js`（网络优先缓存，详见下方"Service Worker"）。

## ⚠️ 重要：这个仓库有"两个账号在同时改"

**另一个独立的 Claude 会话**（负责一个姊妹项目"牛室 Beef House ERP"，跟明记是两套
完全独立的系统/数据库，但架构师出自同一人之手、功能经常同步）**也有权限直接推送到
这个仓库的 `main` 分支**，不会提前打招呼。表现：你 `git log` 时可能看到不是你推的
commit，`git push` 前如果没先 `git fetch`+比对，可能会用旧的 BUILD 号覆盖/冲突。

**规矩**：
1. 每次要改 `index.html`/`sw.js` 前，先 `git fetch origin main` 看看有没有新 commit。
2. 如果远端比本地新，先确认远端改了什么（尤其是 `BUILD`/`SW_VERSION`），再决定怎么
   合并，不要盲目覆盖。
3. `BUILD`（`index.html`）和 `SW_VERSION`（`sw.js`）必须**同步手动升级**，格式
   `MMDD` + `mkNN`（例如 `0930mk65`），每次推送前都要确认两边一致、且比远端当前值大。
4. 这个会话本身此前也被安排在一个任务分支（如
   `claude/xxxxx`）上开发，但由于 GitHub Pages 只认 `main`，且另一个会话也直接推
   `main`，实务上**本项目一直是直接 `git push -u origin main`**，没有走 PR 流程。
   新会话如果被分配了不同的任务分支，建议确认清楚部署策略后再决定要不要沿用这个
   做法（但历史上这么做没出过问题，GitHub Pages 稳定按 `main` 最新内容部署）。

## 推送前必做的检查清单

1. `git fetch origin main`，确认本地基于最新的 `origin/main`。
2. 改完代码后，**语法检查**（因为是单文件，手滑打错一个括号整站就白屏）：
   ```bash
   node --check sw.js
   node -e "
   const fs=require('fs');
   const html=fs.readFileSync('index.html','utf8');
   const m=html.match(/<script>([\s\S]*)<\/script>\s*<\/body>/);
   new Function(m[1]);
   console.log('INLINE_SCRIPT_OK');
   "
   ```
3. `BUILD`（`index.html` 里 `const BUILD="..."`）和 `sw.js` 的 `SW_VERSION` 一起 +1，
   两边字符串必须完全一致。
4. commit message 要写清楚改了什么、为什么，方便以后排查。
5. `git push -u origin main`。
6. 如果是会影响界面/权限/数据结构的改动，建议口头跟用户确认一下效果（用户很依赖
   截图/录屏反馈问题，非常配合测试）。

## 当前版本状态（2026-11-02 整理时）

- 最新 `BUILD` = `0930mk65`
- 最新一次改动：员工档案"登入邮箱"绑定加上**重复绑定拦截**（一个邮箱只能绑一位
  员工），跟牛室那边的同一修法对齐。

## 核心架构速览

- `d()` / `DB[curOutlet]`：每个分店自己的数据桶（进销存、员工、财务等全部按分店隔离）。
- `render()` / `renderTop()` / `renderSidebar()`：整站的重渲染管线。
- `_pages{}`：路由表；`MENU[]`：侧边栏菜单定义；`PROC_SUB{}`：采购进销子页面权限映射。
- 角色权限系统 `ROLES{}`（在 `index.html` 里搜 `const ROLES=`）：
  ```
  owner     老板          — 全权，含所有分店+系统设置；薪资发放锁死只读(交hrmgr处理)
  hrmgr     人事经理      — 权限等同老板；唯一能实际"处理"薪资发放的角色；
                             后台手动分配账号，不走邀请码注册
  area      区域副经理    — 全分店(不含中央厨房)；人力财务只看总数不看个人；
                             薪资发放也是锁死只读
  outletmgr 店面经理      — 本店负责人；可看本店每位员工薪水(锁死只读)
  manager   店长          — 本店采购/盘点/损耗/OpEx录入+报表；薪资只看自己
  headchef  厨师长        — 生产工单/成品入库/配送调拨；可核对AP不能删
  staff     员工          — 只有人事自助：打卡/请假/查看自己薪资
  ckmgr     中央经理      — 中央厨房专属，权限同店长+自己的HR自助
  ckstaff   中央员工      — 中央厨房专属，权限同厨师长+自己的HR自助
  ```
  - `hrScope`: `all`(全部) / `branch`(本店) / `self`(只看自己) —— 决定考勤/排班/
    请假/薪资能看到谁的数据。
  - `canW(p)` / `can(p)`：功能可写/可见判断。
  - `hrEditable()` = `canW('hr') && hrScope()==="all"` —— 员工档案的新增/编辑/删除，
    目前只开放给 **区域副经理及以上**（owner/hrmgr/area）。
  - `canSeeSalary()`：`salaryView==="full"` 才能看到个人薪资明细。
- 11 家分店（`OUTLETS[]`，`index.html` 搜 `const OUTLETS=`）：
  中央厨房(ck) / OKR店(b1) / PAPA店(b2) / PJ店(b3) / Cheras店(b4) / Kajang店(b5) /
  Puchong店(b6) / Subang店(b7) / Klang店(b8) / Bukit Rimau店(b9) /
  Setia Alam店(b10) / Seremban 2店(b11)。
  - **未解决的疑点**：用户曾提到"Setapak店"，但系统里没有这家，之前问过用户这11家
    是否对得上他们实际的分店，**用户一直没回复确认**。如果以后真的要加第12家分店，
    需要同步改邀请码（见下）。
- 邀请码系统：按"职位 + 分店"发码（`b1`~`b11` 各分店各自一组），注册后自动写入
  Supabase 白名单表并锁定对应分店/职位；`area`/`hrmgr`/`ckmgr`/`ckstaff` 则是单一
  固定码（不分分店）；`hrmgr` 完全不走邀请码，只能后台手动分配。
  有完整邀请码列表 Excel 曾经整理给用户过（如果新会话需要，得重新生成，没有存档
  在仓库里）。
- Supabase RLS 靠 `security definer` 函数把关（`is_admin()` / `is_whitelisted()` /
  `erp_users_is_empty()` 等），对应 SQL 在仓库根目录（`security-hardening.sql`、
  `push-schema.sql` 等）。
- XSS 防护：`oEsc(s)` 转义函数，已经补齐全站输出点，验证过不会被注入执行。

## 近期做过的大功能/修复（时间顺序，新的在后）

1. 多分店进销存基础框架、库存成本核算、配方成本、六大作业拆分独立页面。
2. Supabase 真实登录 + 白名单 + RBAC 角色权限系统。
3. 运营开销(OpEx)按自然月独立核算，联动人事薪资自动算人工成本。
4. 月末盘点单价改成**自动＝当月每日进货单价的中位数**（不是平均数）。
5. 人事经理(hrmgr)新角色：权限等同老板，专门独占处理"薪资发放"的实际操作；
   老板/区域副经理的薪资发放改成锁死只读（`salaryLock:true`）。
6. XSS 转义全站补齐、员工档案编辑权限收紧到区域副经理以上。
7. 薪资发放页加年份分组 tab + 手动新增月份 + 删除月份(需连续两次确认)。
8. 忘记密码功能（Supabase Auth `resetPasswordForEmail`/`updateUser`），期间修过
   两次竞态条件 bug（重设密码页被正常登录流程抢回主系统）。
9. 手机端大量体验优化：
   - App 图标从空白红金方块改成正确的"明记"图标(`icon-192.png`/`icon-512.png`/
     `apple-touch-icon.png`)。
   - 侧边栏滑动穿透背景、滑到底又弹回去、顶栏换行盖住按钮等一系列触控bug，都是
     透过分析用户提供的真机录屏(ffmpeg抽帧)逐个根因修复的——不要凭空猜，这些都有
     具体的 CSS 根因（`--topH` 动态变量、`overscroll-behavior:contain`、
     `100dvh`、`touch-action` 等，细节看 git log 对应 commit）。
10. 采购进销的报废/招待品项选择，从 datalist 自由输入改成纯 `<select>` 下拉
    （跟跨店调拨一致的交互）。全站加上"按ESC关闭弹窗"。
11. 顶栏"分店名字"和"版本号码"位置互换（**连样式也要互换**，不只是换位置——
    这点被用户纠正过两次，细节见 commit `d96095d`/`113ebcb`/`3d3437a`）。
12. 自动版本更新检测系统：
    - `checkForUpdate()` 轮询 + Service Worker `updatefound` 事件双重侦测。
    - 检测到新版本后，`showUpdateBanner()` 显示强制更新弹窗（必须点确认才能继续
      用），但如果用户正在填表单（`isBusyEditing()` 判断），会**延后弹出**，不会
      让用户丢失正在输入的数据。
    - 全员可见的更新铃铛（`#updBellBtn`，用 `icon-update.png`，不像订单铃铛
      `#bellBtn` 只有 owner/area/hrmgr 能看）。
    - `sw.js` 从空壳改写成**网络优先缓存**策略。
13. 闲置自动登出：
    - `owner`/`area`/`hrmgr`/`outletmgr` 不会自动登出。
    - `manager`/`headchef`/`staff`/`ckmgr`/`ckstaff` 这**精确5个角色**，30分钟无
      操作强制登出；登出前第29分钟会弹60秒倒数的"继续使用"提醒卡片。
    - 开着弹窗(`#mbg.show`)时不计入闲置时间。
14. 版本更新提示音、新订单提示音，改成模仿 iPhone Note/Tri-tone 风格——**这个改动
    是牛室那边的会话直接推到这个仓库做的**，明记这边原样沿用，没有重复实现。
15. 推送通知(Web Push)修复：
    - `erp_push_subs` 表一开始没建过(`push-schema.sql` 没跑)，导致"开启通知"一直
      失败，已指导用户在 Supabase SQL Editor 跑过了。
    - `send-order-push` Edge Function 一直没部署，是浏览器报 CORS 错误的根因，已
      指导用户在 Supabase 网页控制台手动部署（Secrets 先设三个值
      `VAPID_PUBLIC`/`VAPID_PRIVATE`/`VAPID_SUBJECT`，再贴代码部署，并关闭
      "Verify JWT with legacy secret" 开关——官方也建议关闭）。
    - 已知限制（**不是 bug，是平台限制，跟用户解释过**）：iOS 上一定要"加到主屏幕"
      变成已安装的 PWA 才能收到关闭App后的后台推送，单纯开着 Safari 分页收不到；
      iOS 通知声音要去 系统设置→通知→找到这个App→手动开"声音"。
    - 如果声音开了还是没响：建议排查专注模式/勿扰模式、系统提示音量滑块。
16. **`currentEmpId()` 写死返回1 的 bug 修复**（这是本次交接前最后处理的事，也是
    最重要的一个待确认点）：
    - 原本不管谁登录，"自助查看自己的打卡/排班/请假/薪资"这几个功能全部固定抓
      "员工编号1"的记录，不分青红皂白。
    - 修法：员工档案新增"登入邮箱"字段(`em_email`)，`currentEmpId()` 改成按
      `curUser.email` 去 `d().staff` 里找对应员工，找不到就返回 `null`（不再有
      fallback 去抓"第一位员工"的真实数据）。
    - 找不到绑定时的体验：打卡会提示"账号尚未绑定员工档案，请联系管理员"；
      "我的薪资"页面显示同样的提示，不会泄露别人的薪资。
    - 加了**重复绑定拦截**：一个登入邮箱只能绑一位员工，保存时如果该邮箱已经绑给
      别人会直接拒绝（跟牛室那边同步的修法）。
    - **⚠️ 用户待办**：现有员工档案都还没填登入邮箱。等哪天要开放
      manager/staff/headchef/ckmgr/ckstaff 这些角色自己登录用"自助查看"功能时，
      人事（hrmgr/area/owner）要先去「人事 → 员工档案」把每位员工的登入邮箱补上，
      不然他们会看到"未绑定"的提示而不是自己的真实资料（这是刻意的安全设计，
      宁可看不到也不要看错人）。

## 已知未解决/待确认事项

1. **11家分店名字是否对得上用户实际分店**（见上方"Setapak店"疑点），用户没回复，
   不要主动再追问，等用户自己提起。
2. **员工档案登入邮箱还没有任何人填**，自助查看功能技术上已经修好但实际没人能用
   （因为没绑定），不算 bug，是等用户去填资料。
3. 用户之前提过"会上传一份人工算好的BOM/配方成本文件来导入"，一直没上传，不用
   主动跟进。
4. iOS 推送通知声音偶发性不响的问题排查到一半（怀疑是专注模式/系统音量），用户
   说"先不理，没什么影响"，暂时搁置。

## 跟牛室(Beef House ERP)的关系

- **完全独立的两个项目/两套数据库**，但功能经常互相同步（两边各自的 Claude 会话
  都有权限直接推对方仓库的 main，这点前面"重要"那段已经强调过）。
- 本次交接时，明记这边确认跟牛室同步过的功能：通知提示音风格(iPhone Note/
  Tri-tone)、闲置自动登出设计、`currentEmpId()` 修复思路（含重复邮箱绑定拦截）。
- 如果以后看到仓库里出现自己没做过的 commit，大概率是牛室那边的会话推的，先
  `git log` 确认内容再决定要不要在明记这边也跟进，不要直接假设是 bug 或误操作。
