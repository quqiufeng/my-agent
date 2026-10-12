// agentkit/tools/cdp.js — 通用 Chrome DevTools Protocol 桥（DOM 精准读/点，无需 MCP）
// 用法:
//   node cdp.js title
//   node cdp.js url
//   node cdp.js eval "<js表达式>"
//   node cdp.js text  "<css选择器>"
//   node cdp.js html  "<css选择器>"
//   node cdp.js query "<css选择器>"      # 返回 [{tag,text,attrs}]
//   node cdp.js click "<css选择器>"      # 滚动到可见并 click()
//   node cdp.js goto  "<url>"
//   node cdp.js cookies [域名子串]        # 输出 "k=v; k=v"
// 连接: $HOME/.config/google-chrome/DevToolsActivePort 的浏览器级 WebSocket。
const fs = require('fs');

function wsUrl() {
  if (process.env.AGENTKIT_CDP_WS) return process.env.AGENTKIT_CDP_WS;   // 显式优先
  const pf = (process.env.AGENTKIT_CHROME_DIR || process.env.HOME + '/.config/google-chrome') + '/DevToolsActivePort';
  if (fs.existsSync(pf)) {
    const [port, bpath] = fs.readFileSync(pf, 'utf8').trim().split('\n');
    return 'ws://127.0.0.1:' + port + bpath;
  }
  return undefined;
}

const cmd = process.argv[2] || 'title';
const arg = process.argv[3] || '';

(async () => {
  const url = wsUrl();
  if (!url) { process.stderr.write('no DevToolsActivePort / AGENTKIT_CDP_WS\n'); process.exit(2); }
  const ws = new WebSocket(url);
  let id = 0; const pend = {};
  const send = (method, params, s) => new Promise((res, rej) => {
    const i = ++id; pend[i] = { res, rej };
    ws.send(JSON.stringify({ id: i, method, params: params || {}, sessionId: s }));
    setTimeout(() => { if (pend[i]) { delete pend[i]; rej(new Error('timeout: ' + method)); } }, 8000);
  });
  ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id && pend[m.id]) { m.error ? pend[m.id].rej(m.error) : pend[m.id].res(m.result); delete pend[m.id]; }
  };
  await new Promise(r => ws.onopen = r);

  const { targetInfos } = await send('Target.getTargets');
  const page = (targetInfos || []).find(t => t.type === 'page');
  if (!page) { process.stderr.write('no page target\n'); process.exit(1); }
  const { sessionId } = await send('Target.attachToTarget', { targetId: page.targetId, flatten: true });

  const ev = async expr => {
    const r = await send('Runtime.evaluate',
      { expression: expr, returnByValue: true, awaitPromise: true }, sessionId);
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.text || 'eval error');
    return r.result && r.result.value;
  };
  const out = v => process.stdout.write(typeof v === 'string' ? v : JSON.stringify(v));
  const sel = JSON.stringify(arg);

  switch (cmd) {
    case 'title': out(await ev('document.title')); break;
    case 'url':   out(await ev('location.href')); break;
    case 'eval':  out(await ev(arg)); break;
    case 'text':  out(await ev(`(()=>{const e=document.querySelector(${sel});return e?e.innerText:null})()`) || ''); break;
    case 'html':  out(await ev(`(()=>{const e=document.querySelector(${sel});return e?e.outerHTML:null})()`) || ''); break;
    case 'query': out(await ev(`(()=>{return [...document.querySelectorAll(${sel})].slice(0,50).map(e=>({tag:e.tagName.toLowerCase(),text:(e.innerText||'').slice(0,200)}))})()`) || []); break;
    case 'click': out(await ev(`(()=>{const e=document.querySelector(${sel});if(!e)return false;e.scrollIntoView({block:'center'});e.click();return true})()`) ? 'ok' : 'not-found'); break;
    case 'goto':  { await send('Page.enable', {}, sessionId); const r = await send('Page.navigate', { url: arg }, sessionId); out(r && r.frameId ? 'ok' : JSON.stringify(r)); break; }
    case 'cookies': {
      const b = await send('Storage.getCookies', {}, sessionId);
      const ck = (b.cookies || []).filter(c => !arg || (c.domain || '').includes(arg)).map(c => c.name + '=' + c.value).join('; ');
      out(ck); break;
    }
    default: process.stderr.write('unknown cmd: ' + cmd + '\n'); process.exit(2);
  }
  ws.close(); process.exit(0);
})().catch(e => { process.stderr.write(String(e) + '\n'); process.exit(1); });
