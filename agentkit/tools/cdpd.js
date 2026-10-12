// agentkit/tools/cdpd.js — 常驻 CDP 守护：连 Chrome 一次并保持；本机 9333 收请求复用该连接
// 这样 Chrome 的「允许远程调试」只弹一次（守护启动时），之后所有请求走同一条客户端。
// 请求(每行一个 JSON): {"cmd":"eval","args":"..."}  响应(一行 JSON): {"ok":true,"out":...}
const net = require('net');
const fs = require('fs');

function wsUrl() {
  const pf = process.env.HOME + '/.config/google-chrome/DevToolsActivePort';
  if (fs.existsSync(pf)) {
    const [port, bpath] = fs.readFileSync(pf, 'utf8').trim().split('\n');
    return 'ws://127.0.0.1:' + port + bpath;
  }
  return process.env.AGENTKIT_CDP_WS;
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
let sendFn = null, sessionId = null;

async function connectChrome() {
  const ws = new WebSocket(wsUrl());
  let id = 0; const pend = {};
  const send = (method, params, s) => new Promise((res, rej) => {
    const i = ++id; pend[i] = { res, rej };
    ws.send(JSON.stringify({ id: i, method, params: params || {}, sessionId: s }));
    setTimeout(() => { if (pend[i]) { delete pend[i]; rej(new Error('timeout: ' + method)); } }, 30000);
  });
  ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend[m.id]) { m.error ? pend[m.id].rej(m.error) : pend[m.id].res(m.result); delete pend[m.id]; } };
  ws.onclose = () => { sendFn = null; process.stderr.write('chrome ws closed (no auto-reconnect)\n'); };
  await new Promise(r => ws.onopen = r);
  await send('Page.enable');
  const { targetInfos } = await send('Target.getTargets');
  const page = (targetInfos || []).find(t => t.type === 'page');
  const r = await send('Target.attachToTarget', { targetId: page.targetId, flatten: true });
  sessionId = r.sessionId;
  sendFn = send;
}

const ev = async expr => {
  const r = await sendFn('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, sessionId);
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text || 'eval error');
  return r.result && r.result.value;
};
const key = (type) => ({ type, key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });

const EDITOR = '.ql-editor[contenteditable="true"], rich-textarea [contenteditable="true"], div[contenteditable="true"]';
const RESP = '.model-response-text, message-content, .response-container-content, .markdown-main-panel';

async function handle(cmd, a) {
  a = a || {};
  switch (cmd) {
    case 'title': return await ev('document.title');
    case 'url':   return await ev('location.href');
    case 'eval':  return await ev(a.js || a);
    case 'text':  return await ev(`(()=>{const e=document.querySelector(${JSON.stringify(a.sel)});return e?e.innerText:null})()`) || '';
    case 'html':  return await ev(`(()=>{const e=document.querySelector(${JSON.stringify(a.sel)});return e?e.outerHTML:null})()`) || '';
    case 'query': return await ev(`(()=>[...document.querySelectorAll(${JSON.stringify(a.sel)})].slice(0,50).map(e=>({tag:e.tagName.toLowerCase(),text:(e.innerText||'').slice(0,200)})))()`) || [];
    case 'click': return await ev(`(()=>{const e=document.querySelector(${JSON.stringify(a.sel)});if(!e)return false;e.scrollIntoView({block:'center'});e.click();return true})()`);
    case 'focus': return await ev(`(()=>{const e=document.querySelector(${JSON.stringify(a.sel)});if(!e)return false;e.focus();return true})()`);
    case 'type':  await sendFn('Input.insertText', { text: a.text || '' }, sessionId); return true;
    case 'press': { const t = a.type === 'keyUp' ? 'keyUp' : 'keyDown';
                    await sendFn('Input.dispatchKeyEvent', key(t), sessionId); return true; }
    case 'goto':  { await sendFn('Page.navigate', { url: a.url }, sessionId); return true; }
    case 'wait':  { const t0 = Date.now();
                    while (Date.now() - t0 < (a.timeout || 20000)) { if (await ev(a.js)) return true; await sleep(500); }
                    return false; }
    case 'cookies': { const b = await sendFn('Storage.getCookies', {}, sessionId);
                      return (b.cookies || []).filter(c => !a.domain || (c.domain || '').includes(a.domain)).map(c => c.name + '=' + c.value).join('; '); }
    case 'gemini': {
      await sendFn('Page.navigate', { url: 'https://gemini.google.com/app' }, sessionId);
      const t0 = Date.now();
      while (Date.now() - t0 < 25000) { if (await ev(`!!document.querySelector(${JSON.stringify(EDITOR)})`)) break; await sleep(500); }
      await ev(`document.querySelector(${JSON.stringify(EDITOR)}).focus()`);
      await sendFn('Input.insertText', { text: a.prompt || '' }, sessionId);
      await sleep(400);
      await sendFn('Input.dispatchKeyEvent', key('keyDown'), sessionId);
      await sendFn('Input.dispatchKeyEvent', key('keyUp'), sessionId);
      const GET = `[...document.querySelectorAll(${JSON.stringify(RESP)})].map(e=>e.innerText).join('\\n').trim()`;
      let last = '', stable = 0;
      for (let i = 0; i < 90; i++) { await sleep(1000); const cur = await ev(GET);
        if (cur && cur === last) { if (++stable >= 3) break; } else { stable = 0; last = cur; } }
      return last || '';
    }
    case 'ask': {
      // 在当前 Gemini 会话接着问（不重新导航）；返回最后一条回复
      const t0 = Date.now();
      while (Date.now() - t0 < 15000) { if (await ev(`!!document.querySelector(${JSON.stringify(EDITOR)})`)) break; await sleep(400); }
      await ev(`(()=>{const e=document.querySelector(${JSON.stringify(EDITOR)});e.focus();document.execCommand('selectAll');document.execCommand('delete');return true})()`);
      await sendFn('Input.insertText', { text: a.prompt || '' }, sessionId);
      await sleep(300);
      await sendFn('Input.dispatchKeyEvent', key('keyDown'), sessionId);
      await sendFn('Input.dispatchKeyEvent', key('keyUp'), sessionId);
      const LAST = `(()=>{const els=[...document.querySelectorAll(${JSON.stringify(RESP)})];return els.length?els[els.length-1].innerText.trim():''})()`;
      let last = '', stable = 0;
      for (let i = 0; i < 90; i++) { await sleep(1000); const cur = await ev(LAST);
        if (cur && cur === last) { if (++stable >= 3) break; } else { stable = 0; last = cur; } }
      return last || '';
    }
    default: throw new Error('unknown cmd: ' + cmd);
  }
}

net.createServer(sock => {
  let buf = '';
  sock.on('data', async d => {
    buf += d;
    const nl = buf.indexOf('\n');
    if (nl < 0) return;
    const line = buf.slice(0, nl);
    try {
      const { cmd, args } = JSON.parse(line);
      if (!sendFn) await connectChrome();
      const out = await handle(cmd, args);
      sock.write(JSON.stringify({ ok: true, out }) + '\n');
    } catch (e) { sock.write(JSON.stringify({ ok: false, err: String(e) }) + '\n'); }
    sock.end();
  });
}).listen(9333, '127.0.0.1', () => process.stderr.write('cdpd listening on 9333\n'));

connectChrome().catch(e => process.stderr.write('connect failed: ' + e + '\n'));
