// 明记家乡小食店 ERP · 进货单拍照识别 invoice-ocr
// 作用：手机拍下供应商发票/送货单 → 本函数请 Claude 读图 → 回传 {供应商, 日期, 单号, 品项[品名/数量/单价/金额/对应的库存品名]}。
// 网页拿到后给人核对，确认了才写进「进货单」。本函数不碰数据库里的进货数据。
//
// 部署（Supabase 控制台 → Edge Functions → 新建 invoice-ocr，粘贴本文件）：
//   1. Settings → Edge Functions → Secrets 新增 ANTHROPIC_API_KEY（你在 console.anthropic.com 建的 key；绝不要写进代码/仓库）。
//   2. 「Verify JWT」保持关闭（本函数自己验证登录令牌，和 send-order-push 一样）。
// 安全：只有已登录且在 erp_users 里 active 的账号能用；图片限 6MB；每账号每分钟 6 次；CORS 只允许 ERP 网址；
//       GET ?health=1 只检查设定，不会调用 Claude。
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const API_KEY = (Deno.env.get("ANTHROPIC_API_KEY") ?? "").trim().replace(/^["']+|["']+$/g, "");
const MODEL = (Deno.env.get("INVOICE_MODEL") ?? "claude-sonnet-5-5").trim();
const ALLOWED_ORIGIN = "https://mengkeesystem.github.io";
const MAX_IMG_CHARS = 8_000_000; // base64 字符数，约 6MB 图片
const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

function corsFor(req: Request): Record<string, string> {
  const h: Record<string, string> = {
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Access-Control-Max-Age": "86400",
  };
  if ((req.headers.get("origin") || "") === ALLOWED_ORIGIN) h["Access-Control-Allow-Origin"] = ALLOWED_ORIGIN;
  return h;
}
function reply(req: Request, obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsFor(req), "Content-Type": "application/json" } });
}
const clean = (v: unknown, max: number) => String(v ?? "").replace(/[\u0000-\u001f\u007f<>]/g, " ").replace(/\s+/g, " ").trim().slice(0, max);

async function authenticate(req: Request) {
  const m = /^Bearer\s+(.+)$/i.exec(req.headers.get("authorization") || "");
  if (!m) return null;
  let email = "";
  try {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { Authorization: `Bearer ${m[1]}`, apikey: SUPABASE_ANON_KEY } });
    if (!r.ok) return null;
    email = String((await r.json())?.email || "").toLowerCase();
  } catch (_e) { return null; }
  if (!email) return null;
  const { data } = await supabase.from("erp_users").select("email, role, active").eq("email", email).maybeSingle();
  if (!data || data.active !== true) return null;
  return { email, role: String(data.role || "") };
}

const hits = new Map<string, number[]>();
function tooMany(key: string): boolean {
  const now = Date.now();
  const arr = (hits.get(key) || []).filter((t) => now - t < 60_000);
  if (arr.length >= 6) { hits.set(key, arr); return true; }
  arr.push(now); hits.set(key, arr); return false;
}

const MON: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };
// 日期兜底：模型有时没照格式输出（25/11/2026、25/Nov/2026、24/11/26）。马来西亚是日/月/年；年份要在今年前后才算数，不然当作没读到。
function normDate(v: unknown): string {
  const t = String(v ?? "").trim();
  let y = 0, mo = 0, d = 0, m: RegExpExecArray | null;
  if ((m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(t))) { y = +m[1]; mo = +m[2]; d = +m[3]; }
  else if ((m = /^(\d{1,2})[\/.\-\s]+([A-Za-z]{3,9})[\/.\-\s,]+(\d{2,4})/.exec(t))) { d = +m[1]; mo = MON[m[2].slice(0, 3).toLowerCase()] || 0; y = +m[3]; }
  else if ((m = /^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})/.exec(t))) { d = +m[1]; mo = +m[2]; y = +m[3]; }
  if (y > 0 && y < 100) y += 2000;
  const now = new Date().getFullYear();
  if (!(y >= now - 2 && y <= now + 1) || mo < 1 || mo > 12 || d < 1 || d > 31) return "";
  const dim = new Date(y, mo, 0).getDate();
  if (d > dim) return "";
  return `${y}-${String(mo).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsFor(req) });
  const url = new URL(req.url);
  if (req.method === "GET" && url.searchParams.get("health") === "1") {
    const problems: string[] = [];
    if (!API_KEY) problems.push("ANTHROPIC_API_KEY_not_set");
    if (!SUPABASE_URL || !SERVICE_KEY) problems.push("supabase_env_missing");
    return problems.length ? reply(req, { ok: false, problems }, 503) : reply(req, { ok: true });
  }
  if (req.method !== "POST") return reply(req, { error: "method_not_allowed" }, 405);
  const who = await authenticate(req);
  if (!who) return reply(req, { error: "unauthorized" }, 401);
  if (!API_KEY) return reply(req, { error: "not_configured", message: "ANTHROPIC_API_KEY 还没设置" }, 503);
  if (tooMany(who.email)) return reply(req, { error: "rate_limited", message: "识别太频繁，请一分钟后再试" }, 429);

  let body: any;
  try { body = await req.json(); } catch (_e) { return reply(req, { error: "bad_json" }, 400); }
  const image = String(body?.image || "");
  const mediaType = ["image/jpeg", "image/png", "image/webp"].includes(body?.mediaType) ? body.mediaType : "image/jpeg";
  if (!image || image.length > MAX_IMG_CHARS || !/^[A-Za-z0-9+/=]+$/.test(image)) return reply(req, { error: "bad_image", message: "图片无效或太大" }, 400);
  const supplier = clean(body?.supplier, 80);
  const items: string[] = Array.isArray(body?.items) ? body.items.slice(0, 400).map((s: unknown) => clean(s, 90)).filter(Boolean) : [];

  const prompt = `你是马来西亚中餐小食店的进货录入助手。图片是供应商的发票/送货单/收据（可能是手写、可能有马来文/英文/中文混写，可能是手拿着拍的、有折痕、有手指遮住边角）。
请读出每一行货品，只输出 JSON，不要任何其他文字：
{"supplier":"发票抬头的供应商名（卖方）或空","buyer":"买方/客户名（发票上写的「卖给谁」，例如 MK KELANA SDN BHD (PJ MK)、手写的 明记 PJ）或空","date":"YYYY-MM-DD 或空","invoiceNo":"单号或空","lines":[{"name":"发票上的品名原文（中英文都写上）","qty":数字,"unit":"单位如 kg/pkt/ctn/box 或空","unitPrice":数字或null,"amount":数字或null,"match":"最像的库存品名（必须从下面清单里原样复制）或 null"}],"total":数字或null,"note":"看不清/可疑之处，没有就空"}
规则：
1. 数字不要带 RM 或逗号；看不清的数字用 null，不要猜；不是货品的行（合计、税、折扣、运费、找零、CASH/CHANGE）不要放进 lines。
2. 日期：马来西亚是「日/月/年」。25/11/2026、25/Nov/2026 02:34:00、24/11/26（两位年份＝20xx）都要转成 YYYY-MM-DD；时间部分丢掉；找不到日期就留空，不要用今天。
3. 数量×单价应该≈金额。三个数里读到两个，第三个可以算出来就算出来（例如手写单只写了数量 9.4 和金额 263.20，没写单价：unitPrice 填 null 即可，网页会自己用金额÷数量算）；如果三个都读到但对不上，照实填写，并在 note 写「第N行 数量×单价≠金额」。
4. 价格栏可能被折行成两行（例如 12.0000 / 0 其实是 12.00000），请合起来读。单位栏写 UNIT 但数量带小数（如 3.40 UNIT）通常其实是公斤数，照写 qty 即可，在 unit 填 kg 并在 note 提一句。
5. 手写单上空白的格子、被划掉的格子、斜线不是货品。手写字请尽量读，实在认不出的品名照形状写出来并在 note 说明不确定。
6. match 只有在确定是同一样东西时才填，不确定就 null。品名常中英马来混用，可对照：Sayur Raja=帝王苗、Kangkong=翁菜/空心菜、Daun Bawang=青葱、Daun Ketumber=元茜/香菜、Romain=油麦菜/油麦胆、Daun Keledek=番薯叶/树苗、Tauhu Kotak=盒豆腐、Kacang Bendi=羊角豆、Terung Panjang=长茄子/茄子、Nai Pai=奶白菜、Big Head Carp=松鱼头/大头鱼、Baung=巴冷/Baung 鲶鱼、马友=Threadfin。
${supplier ? "这张单预计来自供应商：" + supplier + "\n" : ""}库存品名清单（一行一个）：
${items.join("\n") || "（无）"}`;

  let r: Response;
  try {
    r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": API_KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 4000,
        messages: [{ role: "user", content: [
          { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
          { type: "text", text: prompt },
        ] }],
      }),
    });
  } catch (_e) { return reply(req, { error: "upstream_unreachable", message: "连不上识别服务" }, 502); }
  if (!r.ok) {
    const t = (await r.text()).slice(0, 200);
    console.log("anthropic error", r.status, t);
    return reply(req, { error: "upstream_error", status: r.status, message: r.status === 401 ? "ANTHROPIC_API_KEY 无效" : r.status === 429 ? "识别额度/频率受限，稍后再试" : "识别服务出错" }, 502);
  }
  const j = await r.json();
  const text = String(j?.content?.find((c: any) => c.type === "text")?.text || "");
  const m = /\{[\s\S]*\}/.exec(text);
  let out: any = null;
  try { out = m ? JSON.parse(m[0]) : null; } catch (_e) { out = null; }
  if (!out || !Array.isArray(out.lines)) return reply(req, { error: "unreadable", message: "没能读懂这张单，请拍清楚一点再试" }, 422);
  const num = (v: unknown) => (v === null || v === undefined || v === "" || isNaN(+(v as number))) ? null : +v;
  const itemSet = new Set(items);
  const lines = out.lines.slice(0, 120).map((l: any) => {
    const qty = num(l?.qty), unitPrice = num(l?.unitPrice), amount = num(l?.amount);
    let chk = "";   // 数量×单价和金额对不上（相差超过 RM0.5 且超过 1%）→ 网页标红提醒人核对
    if (qty != null && unitPrice != null && amount != null && amount > 0) {
      const diff = Math.abs(qty * unitPrice - amount);
      if (diff > 0.5 && diff / amount > 0.01) chk = "mismatch";
    }
    return { name: clean(l?.name, 120), qty, unit: clean(l?.unit, 12), unitPrice, amount, chk, match: itemSet.has(String(l?.match)) ? String(l.match) : null };
  }).filter((l: any) => l.name);
  return reply(req, {
    supplier: clean(out.supplier, 80), buyer: clean(out.buyer, 80), date: normDate(out.date),
    invoiceNo: clean(out.invoiceNo, 40), total: num(out.total), note: clean(out.note, 300), lines,
  });
});
