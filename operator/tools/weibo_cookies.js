// operator/tools/weibo_cookies.js — 从已登录 Chrome (CDP) 取出微博 cookie，拼成 Cookie 头字符串
// 用法: node weibo_cookies.js    # stdout 输出 "k=v; k=v; ..."
// 连接顺序: 127.0.0.1:9222 → $HOME/.config/google-chrome/DevToolsActivePort
const fs = require('fs');

async function wsUrl() {
  try {
    const r = await fetch('http://127.0.0.1:9222/json/version');
    if (r.ok) {
      const j = await r.json();
      if (j.webSocketDebuggerUrl) return j.webSocketDebuggerUrl;
    }
  } catch (e) {}
  const portfile = process.env.HOME + '/.config/google-chrome/DevToolsActivePort';
  const [port, bpath] = fs.readFileSync(portfile, 'utf8').trim().split('\n');
  return 'ws://127.0.0.1:' + port + bpath;
}

(async () => {
    const ws = new WebSocket(await wsUrl());
    let id = 0; const pend = {};
    const send = (m, p, s) => new Promise((res, rej) => {
        const i = ++id; pend[i] = { res, rej };
        ws.send(JSON.stringify({ id: i, method: m, params: p, sessionId: s }));
    });
    ws.onmessage = e => {
        const m = JSON.parse(e.data);
        if (m.id && pend[m.id]) {
            m.error ? pend[m.id].rej(m.error) : pend[m.id].res(m.result);
            delete pend[m.id];
        }
    };
    await new Promise(r => ws.onopen = r);
    const b = await send('Storage.getCookies', {});
    const ck = (b.cookies || [])
        .filter(c => /weibo\.(com|cn)$/.test(c.domain) || /(^|\.)weibo\./.test(c.domain))
        .map(c => c.name + '=' + c.value).join('; ');
    process.stdout.write(ck);
    ws.close(); process.exit(0);
})().catch(e => { process.stderr.write(String(e) + '\n'); process.exit(1); });
