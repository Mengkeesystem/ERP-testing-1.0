/* 明记家乡小食店 ERP · Service Worker
   目前用于：安装为 App、以及订单通知(前台 showNotification)。
   预留 push 事件处理，供日后接入后台推送(需服务器/Edge Function 发送)。 */
self.addEventListener('install', e => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

// 后台推送(需服务器发送 Web Push；未接入时此段不会触发)
self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { body: event.data && event.data.text() }; }
  const title = data.title || '🔔 新订单 New Order';
  const options = { body: data.body || '', tag: data.tag || 'order', renotify: true, requireInteraction: true, vibrate: [300, 120, 300, 120, 300], data: { url: data.url || './' } };
  if (data.icon) { options.icon = data.icon; options.badge = data.icon; }
  event.waitUntil(self.registration.showNotification(title, options));
});

// 点通知 → 打开/聚焦网站
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const c of list) { if ('focus' in c) return c.focus(); }
      if (clients.openWindow) return clients.openWindow('./');
    })
  );
});
