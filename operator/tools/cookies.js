// operator/tools/cookies.js — 从已登录 Chrome(CDP) 取某域名的 cookie，输出 "k=v; k=v; ..."
// 用法: node cookies.js <域名子串>     例: node cookies.js weibo.com
// 连接顺序: $HOME/.config/google-chrome/DevToolsActivePort → 127.0.0.1:9222
const fs = require('fs');
const needle = (process.argv[2] || '').trim();

async function wsUrl() {
  const pf = process.env.HOME + '/.config/google-chrome/DevToolsActivePort';
  if (fs.existsSync(pf)) {
    const [port, bpath] = fs.readFileSync(pf, 'utf8').trim().split('\n');
    return 'ws://127.0.0.1:' + port + bpath;
  }
  const r = await fetch('http://127.0.0.1:9222/json/version');
  const j = await r.json();
  return j.webSocketDebuggerUrl;
}

(async () => {
  const url = await wsUrl();
  const ws = new WebSocket(url);
  let id = 0; const pend = {};
  const send = (m, p) => new Promise((res, rej) => {
    const i = ++id; pend[i] = { res, rej };
    ws.send(JSON.stringify({ id: i, method: m, params: p }));
  });
  ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id && pend[m.id]) { m.error ? pend[m.id].rej(m.error) : pend[m.id].res(m.result); delete pend[m.id]; }
  };
  await new Promise(r => ws.onopen = r);
  const b = await send('Storage.getCookies', {});
  const ck = (b.cookies || [])
    .filter(c => needle === '' || (c.domain || '').includes(needle))
    .map(c => c.name + '=' + c.value).join('; ');
  process.stdout.write(ck);
  ws.close(); process.exit(0);
})().catch(e => { process.stderr.write(String(e) + '\n'); process.exit(1); });
