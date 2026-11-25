// 明记家乡小食店 ERP · 后台推送函数 send-order-push
// 作用：① 有人下单 → 发给老板/人事经理/运营经理；
//       ② 跨店调拨申请/回复（请求里带 outlet）→ 发给那间店有权批准的账号。
// Web Push：关掉网页也能收到。
// 2026-11-24 起新增两种通知：
//   ③ 订货单状态变化（kind:"order_status"）：确认/拒绝/发货 → 通知「下单那间店」；部分收货/已收货 → 通知老板/运营经理；取消 → 两边。
//      标题和内容由本函数按订单资料生成（不接受网页传来的文字），并核对订单真的是那个状态才发。
//   ④ 每日提醒（kind:"digest"）：由 Supabase 定时任务（pg_cron）带 x-cron-secret 呼叫，不需要登录令牌；
//      每间店把「盘点逾期 / 进货几天没录 / 库存为负 / 等收货」整理成一条通知发给该店店长们；老板/运营经理收一条汇总。
//      要设 Secret CRON_SECRET，并跑 push-digest-cron.sql（见仓库）。
//
// 部署（Supabase 控制台 → Edge Functions）：粘贴本文件为函数 send-order-push，
//   并在 Settings → Functions secrets 设 VAPID_PUBLIC / VAPID_PRIVATE / VAPID_SUBJECT。
//   部署时「Verify JWT」保持关闭（函数自己会验证登录令牌，见下）。
//
// 安全（2026-11-02 起）：
//   * 只有「已登录、而且在 ERP 白名单里且启用」的账号才能发推送，其余一律 401/403；
//   * 带 outlet 的调拨通知：必须真的有一张「调拨申请」连着发送方和接收方两间店（老板/人事经理/运营经理除外）；
//   * 标题/内容限制长度、去掉 < > 和控制字符；图标固定，不接受请求里的网址；
//   * 同一个账号每分钟最多发 20 次；
//   * CORS 只允许 ERP 的网址；
//   * GET ?health=1 只检查设定，绝不发推送，给监控用。
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createECDH } from "node:crypto";
import { Buffer } from "node:buffer";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// 粘贴密钥时常会多出空格/换行/引号，甚至把 "VAPID_PRIVATE=" 一起贴进去：先清掉
const tidy = (v: string, name: string) => v.trim().replace(/^["']+|["']+$/g, "").replace(new RegExp("^" + name + "\\s*=\\s*"), "").trim();
const VAPID_PUBLIC = tidy(Deno.env.get("VAPID_PUBLIC") ?? "", "VAPID_PUBLIC");
const VAPID_PRIVATE = tidy(Deno.env.get("VAPID_PRIVATE") ?? "", "VAPID_PRIVATE");
const VAPID_SUBJECT = tidy(Deno.env.get("VAPID_SUBJECT") ?? "", "VAPID_SUBJECT") || "mailto:admin@mengkee.local";
const ALLOWED_ORIGIN = "https://mengkeesystem.github.io";
const ADMIN_ROLES = ["owner", "hrmgr", "area"];
const APPROVER_ROLES = ["outletmgr", "manager", "headchef", "ckmgr"];
const OUTLET_RE = /^(b([1-9]|1[01])|ck)$/;

// 检查密钥；问题只写「哪一项不对」，绝不把密钥内容写出来
const vapidProblems: string[] = [];
let vapidOk = false;
if (!VAPID_PUBLIC) vapidProblems.push("VAPID_PUBLIC_not_set");
if (!VAPID_PRIVATE) vapidProblems.push("VAPID_PRIVATE_not_set");
if (!vapidProblems.length) {
  try {
    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);
    try { // 公钥和私钥必须是「一对」
      const ecdh = createECDH("prime256v1");
      ecdh.setPrivateKey(Buffer.from(VAPID_PRIVATE, "base64url"));
      if (!ecdh.getPublicKey().equals(Buffer.from(VAPID_PUBLIC, "base64url"))) vapidProblems.push("VAPID_public_and_private_are_not_a_pair");
    } catch (_e) {
      vapidProblems.push("VAPID_private_key_unreadable");
    }
  } catch (e) {
    vapidProblems.push("VAPID_rejected: " + String((e as Error)?.message || e).replace(/\s+/g, " ").slice(0, 120));
  }
}
vapidOk = vapidProblems.length === 0;

const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
const CRON_SECRET = (Deno.env.get("CRON_SECRET") ?? "").trim();

// ======== 纯函数（日期/盘点排程算法；和网页里 schedNext 等逻辑保持一致）========
function schedFmt(dt: Date): string { return dt.getFullYear() + "-" + String(dt.getMonth() + 1).padStart(2, "0") + "-" + String(dt.getDate()).padStart(2, "0"); }
function schedAdd(ds: string, n: number): string { const a = ds.split("-").map(Number); return schedFmt(new Date(a[0], a[1] - 1, a[2] + n)); }
function schedDiff(a: string, b: string): number { const f = (x: string) => { const q = x.split("-").map(Number); return Date.UTC(q[0], q[1] - 1, q[2]); }; return Math.round((f(a) - f(b)) / 864e5); }
function schedLastDone(s: any, db: any, itemSup: (n: string) => string): string {
  let last = s.lastDone || "";
  if (s.kind === "monthend") { for (const r of (db.monthEnd || [])) { if (r.date && (!s.supplier || r.supplier === s.supplier) && r.date > last) last = r.date; } }
  else { for (const r of (db.stocktakes || [])) { if (r.date && (!s.supplier || itemSup(r.item) === s.supplier) && r.date > last) last = r.date; } }
  return last;
}
function schedNext(s: any, last: string, today: string): string {
  const start = s.created || today;
  const dowAfter = (base: string, dow: number) => { let k = schedAdd(base, 1); for (let i = 0; i < 7; i++) { const a = k.split("-").map(Number); if (new Date(a[0], a[1] - 1, a[2]).getDay() === dow) return k; k = schedAdd(k, 1); } return k; };
  const base = last || schedAdd(start, -1);
  if (s.freq === "daily") return schedAdd(base, 1);
  if (s.freq === "weekly") return dowAfter(base, +s.dow || 0);
  if (s.freq === "biweekly") return dowAfter(last ? schedAdd(last, 13) : base, +s.dow || 0);
  const a = base.split("-").map(Number); let y = a[0], m = a[1];
  for (let i = 0; i < 14; i++) {
    const ld = new Date(y, m, 0).getDate(); const day = (+s.dom === 0) ? ld : Math.min(+s.dom || 1, ld);
    const c = y + "-" + String(m).padStart(2, "0") + "-" + String(day).padStart(2, "0");
    if (c > base) return c; m++; if (m > 12) { m = 1; y++; }
  }
  return schedAdd(base, 30);
}
function malaysiaToday(): string { return new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10); }
// 一间店的「今天该处理」清单（纯计算）
function outletTodos(db: any, orders: any[], oid: string, today: string): string[] {
  const out: string[] = [];
  const itemSup = (_n: string) => ""; // 服务器端没有品项→供应商映射：有指定供应商的盘点排程只看手动「标记已盘点」和月末盘点记录
  for (const s of (db.countSchedules || [])) {
    if (s.active === false) continue;
    const last = schedLastDone(s, db, itemSup); const next = schedNext(s, last, today); const n = schedDiff(next, today);
    if (n < 0) out.push(`盘点「${s.name}」已逾期 ${-n} 天`); else if (n === 0) out.push(`今天要盘点「${s.name}」`);
  }
  if (oid !== "ck") {
    let lastP = ""; for (const r of (db.purchases || [])) { if (r.date && r.date > lastP) lastP = r.date; }
    if (lastP) { const ago = schedDiff(today, lastP); if (ago > 3) out.push(`进货已 ${ago} 天没录`); }
  }
  const neg = (db.items || []).filter((i: any) => (+i.qty || 0) < 0).length;
  if (neg) out.push(`${neg} 项库存是负数`);
  const rc = orders.filter((o: any) => o && o.outlet === oid && (o.status === "shipped" || o.status === "partial")).length;
  if (rc) out.push(`${rc} 张订货单等你收货`);
  return out;
}

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
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsFor(req), "Content-Type": "application/json" },
  });
}
function clean(v: unknown, max: number): string {
  return String(v ?? "")
    .replace(/[\u0000-\u001f\u007f<>]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
}

// 验证调用者：登录令牌 → 邮箱 → 必须在白名单（active）里
async function authenticate(req: Request) {
  const m = /^Bearer\s+(.+)$/i.exec(req.headers.get("authorization") || "");
  if (!m) return null;
  let email = "";
  try {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: `Bearer ${m[1]}`, apikey: SUPABASE_ANON_KEY },
    });
    if (!r.ok) return null;
    const u = await r.json();
    email = String(u?.email || "").toLowerCase();
  } catch (_e) {
    return null;
  }
  if (!email) return null;
  const { data } = await supabase
    .from("erp_users")
    .select("email, role, outlet, active")
    .eq("email", email)
    .maybeSingle();
  if (!data || data.active !== true) return null;
  return { email, role: String(data.role || ""), outlet: String(data.outlet || "") };
}

// 简单限流（尽力而为：函数实例重启会清零）
const hits = new Map<string, number[]>();
function tooMany(key: string): boolean {
  const now = Date.now();
  const arr = (hits.get(key) || []).filter((t) => now - t < 60_000);
  if (arr.length >= 20) {
    hits.set(key, arr);
    return true;
  }
  arr.push(now);
  hits.set(key, arr);
  return false;
}

const OUTLET_ROLES = ["outletmgr", "manager", "headchef"];
async function loadOrders(): Promise<any[]> {
  const { data } = await supabase.from("erp_store").select("value").eq("key", "erpv2:orders").maybeSingle();
  let v: any = data?.value; if (typeof v === "string") { try { v = JSON.parse(v); } catch (_e) { v = []; } }
  return Array.isArray(v) ? v : [];
}
async function sendTo(emails: Set<string>, title: string, body: string, tag: string, kind = ""): Promise<number> {
  if (!emails.size) return 0;
  const { data: all } = await supabase.from("erp_push_subs").select("endpoint, sub, email, role");
  const subs = ((all ?? []) as any[]).filter((s) => emails.has(String(s.email || "").toLowerCase()));
  const payload = JSON.stringify({ title, body, icon: "icon-192.png", url: "./", tag, kind });
  let sent = 0;
  await Promise.allSettled(subs.map(async (row: any) => {
    try { await webpush.sendNotification(row.sub, payload); sent++; }
    catch (e: any) { if (e?.statusCode === 404 || e?.statusCode === 410) await supabase.from("erp_push_subs").delete().eq("endpoint", row.endpoint); }
  }));
  return sent;
}
async function emailsOf(outlet: string, roles: string[]): Promise<Set<string>> {
  const { data } = await supabase.from("erp_users").select("email").eq("active", true).eq("outlet", outlet).in("role", roles);
  return new Set((data ?? []).map((u: any) => String(u.email || "").toLowerCase()));
}
async function adminEmails(): Promise<Set<string>> {
  const { data } = await supabase.from("erp_users").select("email").eq("active", true).in("role", ADMIN_ROLES);
  return new Set((data ?? []).map((u: any) => String(u.email || "").toLowerCase()));
}
// 新版本上线通知：GitHub Actions 在网站部署好、确认新版本已上线之后带 x-cron-secret 来呼叫（.github/workflows/notify-update.yml）。
// 所有 active 账号、所有已登记手机都收；同一个版本号只推一次（记在 erp_store 的 erpv2:lastpush:version）。
async function versionPush(req: Request, inp: any): Promise<Response> {
  const build = String(inp?.build ?? "").trim();
  if (!/^\d{4}mk\d{2,3}$/.test(build)) return reply(req, { error: "bad build" }, 400);
  const { data: last } = await supabase.from("erp_store").select("value").eq("key", "erpv2:lastpush:version").maybeSingle();
  if ((last?.value as any)?.build === build && !inp?.force) return reply(req, { ok: true, skipped: "already_sent", build });
  const { data: users } = await supabase.from("erp_users").select("email").eq("active", true);
  const emails = new Set((users ?? []).map((u: any) => String(u.email || "").toLowerCase()));
  const sent = await sendTo(emails, "🔄 明记 ERP 有新版本", `版本 ${build} 已上线，打开 App 点「确认更新」即可。`, "version", "version");
  await supabase.from("erp_store").upsert({ key: "erpv2:lastpush:version", value: { build, at: new Date().toISOString(), sent }, updated_at: new Date().toISOString() });
  return reply(req, { ok: true, sent, build });
}
const ST_TXT: Record<string, string> = { confirmed: "已确认", rejected: "被拒绝", shipped: "已发货", partial: "部分收货", received: "已收货", cancelled: "已取消" };
async function orderStatusPush(req: Request, who: any, input: any): Promise<Response> {
  const oid = clean(input?.orderId, 60); const st = String(input?.status || "");
  if (!ST_TXT[st]) return reply(req, { error: "bad status" }, 400);
  const o = (await loadOrders()).find((x: any) => x && x.id === oid);
  if (!o) return reply(req, { error: "order not found" }, 404);
  if (o.status !== st) return reply(req, { error: "status mismatch" }, 409);   // 订单真的是这个状态才发
  const isAdmin = ADMIN_ROLES.includes(who.role), isCk = who.role === "ckmgr" || who.role === "ckstaff";
  const mineOutlet = o.outlet && who.outlet === o.outlet;
  if (!isAdmin && !isCk && !mineOutlet) return reply(req, { error: "forbidden" }, 403);
  const targets = new Set<string>();
  if (["confirmed", "rejected", "shipped", "cancelled"].includes(st) && OUTLET_RE.test(String(o.outlet || ""))) {
    (await emailsOf(o.outlet, OUTLET_ROLES)).forEach((e) => targets.add(e));
    const ob = String(o.by?.email || "").toLowerCase(); if (ob) targets.add(ob);
  }
  if (["partial", "received", "cancelled"].includes(st)) (await adminEmails()).forEach((e) => targets.add(e));
  targets.delete(who.email);   // 不通知自己
  const title = clean("订货单" + ST_TXT[st], 40);
  const body = clean([o.outletName, o.supplier, o.invoiceNo].filter(Boolean).join(" · "), 120);
  const sent = await sendTo(targets, title, body, "ord-" + oid);
  return reply(req, { sent, total: targets.size });
}
async function runDigest(req: Request): Promise<Response> {
  const today = malaysiaToday(); const orders = await loadOrders();
  const ids = ["ck", ...Array.from({ length: 11 }, (_, i) => "b" + (i + 1))];
  const summary: string[] = []; let sent = 0;
  for (const oid of ids) {
    const { data } = await supabase.from("erp_store").select("value").eq("key", "erpv2:" + oid).maybeSingle();
    let db: any = data?.value; if (typeof db === "string") { try { db = JSON.parse(db); } catch (_e) { db = null; } }
    if (!db || typeof db !== "object") continue;
    const todos = outletTodos(db, orders, oid, today); if (!todos.length) continue;
    summary.push(`${oid.toUpperCase()}：${todos.length} 项`);
    const to = await emailsOf(oid, oid === "ck" ? ["ckmgr"] : OUTLET_ROLES);
    sent += await sendTo(to, "今天要处理 " + todos.length + " 件事", clean(todos.slice(0, 4).join("；"), 150), "digest-" + oid);
  }
  const pend = orders.filter((o: any) => o && (o.status === "pending" || !o.status)).length;
  if (summary.length || pend) {
    const parts = []; if (pend) parts.push(`${pend} 张订货单待确认`); if (summary.length) parts.push("需关注：" + summary.slice(0, 5).join("、") + (summary.length > 5 ? "…" : ""));
    sent += await sendTo(await adminEmails(), "运营提醒", clean(parts.join("；"), 150), "digest-admin");
  }
  return reply(req, { ok: true, sent, outlets: summary.length, pending: pend });
}

async function health(req: Request): Promise<Response> {
  const problems: string[] = [];
  problems.push(...vapidProblems);
  if (!SUPABASE_URL || !SERVICE_KEY) problems.push("supabase_env_missing");
  try {
    const { error } = await supabase.from("erp_push_subs").select("endpoint").limit(1);
    if (error) problems.push("erp_push_subs_unreachable");
  } catch (_e) {
    problems.push("erp_push_subs_unreachable");
  }
  try {
    const { error } = await supabase.from("erp_users").select("email").limit(1);
    if (error) problems.push("erp_users_unreachable");
  } catch (_e) {
    problems.push("erp_users_unreachable");
  }
  return problems.length ? reply(req, { ok: false, problems }, 503) : reply(req, { ok: true, digest: !!CRON_SECRET });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsFor(req) });
  const url = new URL(req.url);
  if (req.method === "GET") {
    if (url.searchParams.get("health") === "1") return await health(req);
    return reply(req, { error: "method not allowed" }, 405);
  }
  if (req.method !== "POST") return reply(req, { error: "method not allowed" }, 405);

  try {
    // —— 每日提醒：Supabase 定时任务带密钥来呼叫（不走登录）——
    const cronHdr = req.headers.get("x-cron-secret");
    if (cronHdr !== null) {
      if (!CRON_SECRET) return reply(req, { error: "cron not configured" }, 503);
      if (cronHdr.length !== CRON_SECRET.length || cronHdr !== CRON_SECRET) return reply(req, { error: "unauthorized" }, 401);
      if (!vapidOk) return reply(req, { error: "push not configured" }, 503);
      const inp = await req.json().catch(() => ({}));
      if (inp?.kind === "digest") return await runDigest(req);
      if (inp?.kind === "version") return await versionPush(req, inp);
      return reply(req, { error: "bad request" }, 400);
    }
    const who = await authenticate(req);
    if (!who) return reply(req, { error: "unauthorized" }, 401);
    if (tooMany(who.email)) return reply(req, { error: "too many requests" }, 429);
    if (!vapidOk) return reply(req, { error: "push not configured" }, 503);

    const input = await req.json().catch(() => ({}));
    if (input?.kind === "order_status") return await orderStatusPush(req, who, input);
    const title = clean(input?.title, 60) || "🔔 新订单 New Order";
    const text = clean(input?.body, 160);
    const outlet = input?.outlet ? String(input.outlet).toLowerCase() : "";

    const { data: all } = await supabase.from("erp_push_subs").select("endpoint, sub, email, role");
    let subs = (all ?? []) as any[];

    if (outlet) {
      // —— 调拨通知：发给「那间店」有批准权限的账号 ——
      if (!OUTLET_RE.test(outlet)) return reply(req, { error: "bad outlet" }, 400);
      if (!ADMIN_ROLES.includes(who.role)) {
        const mine = (who.role === "ckmgr" || who.role === "ckstaff") ? "ck" : who.outlet;
        if (!OUTLET_RE.test(mine) || mine === outlet) return reply(req, { error: "forbidden" }, 403);
        // 必须真的有一张连着这两间店的调拨申请
        const a = await supabase.from("erp_store").select("key").like("key", `erpv2:req:${mine}:${outlet}:%`).limit(1);
        const b = await supabase.from("erp_store").select("key").like("key", `erpv2:req:${outlet}:${mine}:%`).limit(1);
        if (!(a.data && a.data.length) && !(b.data && b.data.length)) return reply(req, { error: "forbidden" }, 403);
      }
      const { data: us } = await supabase
        .from("erp_users")
        .select("email")
        .eq("active", true)
        .eq("outlet", outlet)
        .in("role", APPROVER_ROLES);
      const emails = new Set((us ?? []).map((u: any) => String(u.email || "").toLowerCase()));
      subs = subs.filter((s) => emails.has(String(s.email || "").toLowerCase()));
    } else {
      // —— 新订单：只发给老板/人事经理/运营经理 ——
      subs = subs.filter((s) => ADMIN_ROLES.includes(String(s.role || "")));
    }

    const payload = JSON.stringify({
      title,
      body: text,
      icon: "icon-192.png",
      url: "./",
      tag: outlet ? "xfer-" + Date.now() : "order",
    });
    let sent = 0;
    await Promise.allSettled(
      subs.map(async (row: any) => {
        try {
          await webpush.sendNotification(row.sub, payload);
          sent++;
        } catch (e: any) {
          if (e?.statusCode === 404 || e?.statusCode === 410) {
            await supabase.from("erp_push_subs").delete().eq("endpoint", row.endpoint);
          }
        }
      }),
    );
    return reply(req, { sent, total: subs.length });
  } catch (_e) {
    return reply(req, { error: "server error" }, 500);
  }
});
