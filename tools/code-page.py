#!/usr/bin/env python3
"""把一份要业主复制去部署的代码，做成「有大大复制按钮」的网页（给 Artifact 发布用）。
用法：python3 tools/code-page.py <代码文件> <输出.html> "<页面标题>" "<一句话说明>" "<步骤1>" "<步骤2>" ...
然后用 Artifact 工具发布输出的 html，把 artifact 链接给业主（业主在 Claude 的浏览器里打开就能一键复制）。
"""
import sys,html
code_f,out_f,title,desc=sys.argv[1:5]
steps=sys.argv[5:]
code=open(code_f,encoding='utf-8').read()
lis=''.join(f'<li>{html.escape(s)}</li>' for s in steps)
page=f'''<title>{html.escape(title)}</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
:root{{--bg:#f6f7f9;--fg:#1b2330;--mut:#5b6677;--card:#fff;--line:#dde2ea;--accent:#7c1619;--accent-fg:#fff;--ok:#067647;--code:#f0f2f6;}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--bg:#111722;--fg:#e8edf5;--mut:#9aa6b8;--card:#19212f;--line:#2b364a;--accent:#e0555a;--accent-fg:#fff;--ok:#4ade80;--code:#0e141e;color-scheme:dark}}}}
:root[data-theme="dark"]{{--bg:#111722;--fg:#e8edf5;--mut:#9aa6b8;--card:#19212f;--line:#2b364a;--accent:#e0555a;--accent-fg:#fff;--ok:#4ade80;--code:#0e141e;color-scheme:dark}}
body{{background:var(--bg);color:var(--fg);font:16px/1.65 -apple-system,"PingFang SC","Noto Sans SC",system-ui,sans-serif;padding-block:20px 40px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));}}
main{{max-width:760px;margin:0 auto;display:grid;gap:16px;}}
h1{{font-size:22px;margin:0;text-wrap:balance}} .sub{{color:var(--mut);margin:4px 0 0}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;min-width:0}}
ol{{margin:0;padding-left:22px;display:grid;gap:8px}}
.bar{{position:sticky;top:env(safe-area-inset-top,0px);z-index:5;display:flex;gap:10px;align-items:center;flex-wrap:wrap;background:var(--bg);padding:8px 0}}
button{{font:inherit;font-weight:700;border:0;border-radius:10px;padding:14px 18px;background:var(--accent);color:var(--accent-fg);cursor:pointer;flex:1 1 220px;min-height:48px}}
button.ghost{{background:transparent;color:var(--fg);border:1px solid var(--line);flex:0 0 auto;font-weight:600}}
#msg{{color:var(--ok);font-weight:600;min-height:1.4em}}
textarea{{width:100%;box-sizing:border-box;height:340px;resize:vertical;background:var(--code);color:var(--fg);border:1px solid var(--line);border-radius:10px;padding:12px;font:12.5px/1.5 ui-monospace,Menlo,Consolas,monospace;white-space:pre;overflow:auto}}
.mini{{color:var(--mut);font-size:13px}}
</style>
<main>
<div><h1>{html.escape(title)}</h1><p class="sub">{html.escape(desc)}</p></div>
<div class="card"><b>怎么做</b><ol>{lis}</ol></div>
<div class="bar"><button id="cp">一键复制全部代码</button><button class="ghost" id="sel">全选</button></div>
<div id="msg" role="status"></div>
<textarea id="code" readonly spellcheck="false"></textarea>
<p class="mini">复制不成功的话：点「全选」，再用手机的「拷贝」，或电脑 Ctrl+C。</p>
</main>
<script>
const CODE={__import__('json').dumps(code)};
const ta=document.getElementById('code'),msg=document.getElementById('msg');ta.value=CODE;
function done(t){{msg.textContent=t;setTimeout(()=>{{msg.textContent=''}},4000)}}
document.getElementById('sel').onclick=()=>{{ta.focus();ta.select();ta.setSelectionRange(0,CODE.length);done('已全选，请按「拷贝」')}};
document.getElementById('cp').onclick=async()=>{{
  try{{await navigator.clipboard.writeText(CODE);done('已复制！回到 Supabase 贴上就可以')}}
  catch(e){{ta.focus();ta.select();ta.setSelectionRange(0,CODE.length);let ok=false;try{{ok=document.execCommand('copy')}}catch(x){{}}done(ok?'已复制！回到 Supabase 贴上就可以':'没能自动复制，已帮你全选，请按「拷贝」')}}
}};
</script>
'''
open(out_f,'w',encoding='utf-8').write(page)
