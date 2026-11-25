---
name: owner-deploy-guide
description: 当需要业主（非工程师）去部署、设置或改动任何东西时使用——Supabase Edge Function、SQL、Secrets、GitHub 设置、Vercel 等。规则：只给代码链接不要贴整份代码，并一步一步带业主做。
---

# 业主部署规矩（业主明确要求，所有对话通用）

## 1. 代码只给链接，不贴进聊天
- **任何要业主复制粘贴的内容（函数代码、SQL、命令、设定文字）都一样：给链接，不贴进聊天。**
- **首选做成 Artifact 复制页**（业主在 Claude 的浏览器/App 里能直接打开，有「一键复制全部代码」按钮）：`python3 tools/code-page.py <代码文件> <输出.html> "<标题>" "<说明>" "<步骤1>" "<步骤2>"…` 生成 html，再用 Artifact 工具发布，把 artifact 链接给业主；代码改了要重新生成并用同一个 file_path 重新发布（链接不变）。
- 再附上 GitHub 链接当备用。
- 需要业主复制代码去部署时，**先确认已经 push 到 main**，再给 GitHub 链接，不要把整份代码贴在聊天里（会刷屏）。
- 本仓库是公开的，可以直接给：
  - 看代码：`https://github.com/Mengkeesystem/ERP-testing-1.0/blob/main/<文件路径>`
  - 纯文字（打开后全选复制）：`https://raw.githubusercontent.com/Mengkeesystem/ERP-testing-1.0/main/<文件路径>`
- 其他仓库（牛室、官网）换成对应的 owner/repo。私有仓库的链接业主要登录 GitHub 才打得开，要提醒。

## 2. 一步一步带
- 用编号步骤。每一步写：**去哪里 → 点什么 → 做完应该看到什么**。
- 最后一步写「怎么确认成功」（例如打开某个网址看到 `{"ok":true}`）和「失败时看到什么、怎么办（截图给我）」。
- 一次只讲当前这件事，不要夹带别的。

## 3. 语气
- 全部用白话中文，先说结果，再说要做什么。业主不是工程师，不要假设懂术语。
- 需要业主做的事，放在回复最后，单独成一节。
