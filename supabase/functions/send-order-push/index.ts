// 明记家乡小食店 ERP · 后台推送函数 send-order-push
// 作用：① 有人下单 → 发给老板/人事经理/区域副经理；② 跨店调拨申请/回复（带 outlet）→ 发给那间店有权批准的账号。Web Push，关掉网页也能收到。
// 部署（Supabase 控制台 → Edge Functions）：粘贴本文件为函数 send-order-push，
//   并在 Settings → Functions secrets 设 VAPID_PUBLIC / VAPID_PRIVATE / VAPID_SUBJECT。
//   部署时关闭 JWT 验证（Verify JWT = off / --no-verify-jwt）。详见 PUSH_SETUP.md。
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC") ?? "";
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE") ?? "";
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@mengkee.local";
webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { title, body, icon, outlet } = await req.json().catch(() => ({}));
    // 没带 outlet（新订单）：只发给 老板/人事经理/区域副经理 的设备；
    // 带了 outlet（跨店调拨申请/回复）：只发给那间店「有权批准」的账号（店面经理/店长/厨师长/中央经理）。
    let q = supabase.from("erp_push_subs").select("endpoint, sub, email, role");
    const { data: all } = await q;
    let subs = (all ?? []) as any[];
    if (outlet) {
      const { data: us } = await supabase
        .from("erp_users")
        .select("email")
        .eq("active", true)
        .eq("outlet", String(outlet))
        .in("role", ["outletmgr", "manager", "headchef", "ckmgr"]);
      const emails = new Set((us ?? []).map((u: any) => String(u.email || "").toLowerCase()));
      subs = subs.filter((s) => emails.has(String(s.email || "").toLowerCase()));
    } else {
      subs = subs.filter((s) => ["owner", "hrmgr", "area"].includes(String(s.role || "")));
    }
    const payload = JSON.stringify({
      title: title || "🔔 新订单 New Order",
      body: body || "",
      icon: icon || "",
      url: "./",
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
      })
    );
    return new Response(JSON.stringify({ sent, total: subs.length }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
