// 明记家乡小食店 ERP · 后台推送函数 send-order-push
// 作用：① 有人下单 → 发给老板/人事经理/区域副经理；
//       ② 跨店调拨申请/回复（请求里带 outlet）→ 发给那间店有权批准的账号。
// Web Push：关掉网页也能收到。
//
// 部署（Supabase 控制台 → Edge Functions）：粘贴本文件为函数 send-order-push，
//   并在 Settings → Functions secrets 设 VAPID_PUBLIC / VAPID_PRIVATE / VAPID_SUBJECT。
//   部署时「Verify JWT」保持关闭（函数自己会验证登录令牌，见下）。
//
// 安全（2026-11-02 起）：
//   * 只有「已登录、而且在 ERP 白名单里且启用」的账号才能发推送，其余一律 401/403；
//   * 带 outlet 的调拨通知：必须真的有一张「调拨申请」连着发送方和接收方两间店（老板/人事经理/区域副经理除外）；
//   * 标题/内容限制长度、去掉 < > 和控制字符；图标固定，不接受请求里的网址；
//   * 同一个账号每分钟最多发 20 次；
//   * CORS 只允许 ERP 的网址；
//   * GET ?health=1 只检查设定，绝不发推送，给监控用。
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC") ?? "";
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE") ?? "";
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@mengkee.local";
const ALLOWED_ORIGIN = "https://mengkeesystem.github.io";
const ADMIN_ROLES = ["owner", "hrmgr", "area"];
const APPROVER_ROLES = ["outletmgr", "manager", "headchef", "ckmgr"];
const OUTLET_RE = /^(b([1-9]|1[01])|ck)$/;

let vapidOk = false;
try {
  if (VAPID_PUBLIC && VAPID_PRIVATE) {
    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);
    vapidOk = true;
  }
} catch (_e) {
  vapidOk = false;
}

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

async function health(req: Request): Promise<Response> {
  const problems: string[] = [];
  if (!vapidOk) problems.push("vapid_keys_missing_or_invalid");
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
  return problems.length ? reply(req, { ok: false, problems }, 503) : reply(req, { ok: true });
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
    const who = await authenticate(req);
    if (!who) return reply(req, { error: "unauthorized" }, 401);
    if (tooMany(who.email)) return reply(req, { error: "too many requests" }, 429);
    if (!vapidOk) return reply(req, { error: "push not configured" }, 503);

    const input = await req.json().catch(() => ({}));
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
      // —— 新订单：只发给老板/人事经理/区域副经理 ——
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
