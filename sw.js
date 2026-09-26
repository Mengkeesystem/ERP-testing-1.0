/* 明记家乡小食店 ERP · Service Worker
   用于：安装为 App、订单通知(前台 showNotification)、
   以及"网络优先"抓取——每次打开 App 只要手机有网，就直接去服务器
   要最新的 index.html，不会死抱着旧的缓存不放；只有离线的时候才退回
   用缓存(离线也能打开，不会白屏)。缓存名字带版本号，每次改版跟着
   index.html 的 BUILD 一起手动升级，旧版本缓存会在 activate 时自动清掉。 */
const SW_VERSION = '0926mk53'; // ⚠️ 跟 index.html 的 BUILD 一起手动升级，保持一致
const CACHE_NAME = 'mengkee-erp-' + SW_VERSION;
const CORE_ASSETS = ['./', './index.html', './order-data.js', './manifest.webmanifest', './icon-192.png', './icon-512.png', './apple-touch-icon.png'];

self.addEventListener('install', e => {
  self.skipWaiting(); // 新版本装好立刻生效，不等旧分页全部关掉
  e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(CORE_ASSETS)).catch(() => {}));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// 网络优先：本站自己的文件(index.html/order-data.js等)每次都先去问服务器要最新的；
// 离线/网络失败才退回缓存，缓存也没有就退回 index.html(离线时至少能打开首页)。
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== location.origin) return; // 外部 CDN 资源不拦截，交给浏览器自己处理
  event.respondWith(
    fetch(event.request, { cache: 'no-store' })
      .then(res => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then(c => c.put(event.request, copy)).catch(() => {});
        return res;
      })
      .catch(() => caches.match(event.request).then(r => r || caches.match('./index.html')))
  );
});

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
