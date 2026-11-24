-- 每日提醒（手机推送）：让 Supabase 每天定时呼叫 send-order-push 的「digest」模式。
-- ⚠️ 这个文件里的 <换成你的CRON_SECRET> 要换成你自己设的那串密码（和 Edge Function 的 Secret CRON_SECRET 一样）。
--    换好之后只在 Supabase SQL Editor 里跑，不要把真正的密码存回 GitHub（仓库是公开的）。
-- 时间：每天马来西亚 09:00（＝UTC 01:00）。要改时间就改下面 cron 表达式的前两个数字（分 时，UTC）。
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 已经建过就先删掉旧的（可重复运行）
select cron.unschedule(jobid) from cron.job where jobname = 'erp-daily-digest';

select cron.schedule(
  'erp-daily-digest',
  '0 1 * * *',
  $$
  select net.http_post(
    url := 'https://kmcdokwiyetlmsrdlgqw.supabase.co/functions/v1/send-order-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', '<换成你的CRON_SECRET>'),
    body := '{"kind":"digest"}'::jsonb
  );
  $$
);

-- 检查有没有排上：  select jobname, schedule, active from cron.job;
-- 看最近几次执行：  select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
-- 取消：            select cron.unschedule('erp-daily-digest');
