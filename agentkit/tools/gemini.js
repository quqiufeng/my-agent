// agentkit/tools/gemini.js — 用 CDP/DOM 跑 Gemini（单连接，避免多次授权弹窗）
// 用法: node gemini.js "<提问>"       # 打印 Gemini 的回答文本
// 流程: 连 DevToolsActivePort → 导航 gemini.google.com/app → 输入 → 回车 → 等回复 → 打印
const fs = require('fs');

function wsUrl() {
  if (process.env.AGENTKIT_CDP_WS) return process.env.AGENTKIT_CDP_WS;
  const pf = (process.env.AGENTKIT_CHROME_DIR || process.env.HOME + '/.config/google-chrome') + '/DevToolsActivePort';
  if (fs.existsSync(pf)) {
    const [port, bpath] = fs.readFileSync(pf, 'utf8').trim().split('\n');
    return 'ws://127.0.0.1:' + port + bpath;
  }
  return undefined;
}
async function resolveWs() {
  if (process.env.AGENTKIT_CDP_WS) return process.env.AGENTKIT_CDP_WS;
  try { const r = await fetch('http://127.0.0.1:9222/json/version'); const j = await r.json(); if (j.webSocketDebuggerUrl) return j.webSocketDebuggerUrl; } catch (e) {}
  return wsUrl();
}

const prompt = process.argv[2] || '';
if (!prompt) { process.stderr.write('用法: gemini.js "<提问>"\n'); process.exit(2); }

const EDITOR = '.ql-editor[contenteditable="true"], rich-textarea [contenteditable="true"], div[contenteditable="true"]';
const RESP = '.model-response-text, message-content, .response-container-content, .markdown-main-panel';

(async () => {
  const ws = new WebSocket(await resolveWs());
  let id = 0; const pend = {};
  const send = (method, params, s) => new Promise((res, rej) => {
    const i = ++id; pend[i] = { res, rej };
    ws.send(JSON.stringify({ id: i, method, params: params || {}, sessionId: s }));
    setTimeout(() => { if (pend[i]) { delete pend[i]; rej(new Error('timeout: ' + method)); } }, 30000);
  });
  ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend[m.id]) { m.error ? pend[m.id].rej(m.error) : pend[m.id].res(m.result); delete pend[m.id]; } };
  await new Promise(r => ws.onopen = r);

  const TARGET_FILE = '/tmp/myagent_gemini_target';
  const fresh = process.env.GEMINI_NEW_TARGET === '1';
  let page;
  if (!fresh && fs.existsSync(TARGET_FILE)) {
    const tid = fs.readFileSync(TARGET_FILE, 'utf8').trim();
    const { targetInfos } = await send('Target.getTargets');
    page = (targetInfos || []).find(t => t.targetId === tid && t.type === 'page');
  }
  if (fresh && fs.existsSync(TARGET_FILE)) {
    const old = fs.readFileSync(TARGET_FILE, 'utf8').trim();
    try { await send('Target.closeTarget', { targetId: old }); } catch (e) {}
    fs.unlinkSync(TARGET_FILE);
  }
  if (!page) {
    const t = await send('Target.createTarget', { url: 'about:blank' });
    page = { targetId: t.targetId };
    fs.writeFileSync(TARGET_FILE, page.targetId);
  }
  let sid;
  try {
    ({ sessionId: sid } = await send('Target.attachToTarget', { targetId: page.targetId, flatten: true }));
  } catch (e) {
    const t = await send('Target.createTarget', { url: 'about:blank' });
    page = { targetId: t.targetId };
    fs.writeFileSync(TARGET_FILE, page.targetId);
    ({ sessionId: sid } = await send('Target.attachToTarget', { targetId: page.targetId, flatten: true }));
  }

  const ev = async expr => {
    const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, sid);
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.text || 'eval error');
    return r.result && r.result.value;
  };
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  async function waitFor(expr, timeoutMs) {
    const t0 = Date.now();
    while (Date.now() - t0 < timeoutMs) { if (await ev(expr)) return true; await sleep(500); }
    return false;
  }

  await send('Page.enable', {}, sid);
  await send('Page.navigate', { url: 'https://gemini.google.com/app' }, sid);
  if (!await waitFor(`!!document.querySelector(${JSON.stringify(EDITOR)})`, 25000)) {
    process.stderr.write('未找到 Gemini 输入框\n'); process.exit(1);
  }
  await ev(`document.querySelector(${JSON.stringify(EDITOR)}).focus()`);
  await send('Input.insertText', { text: prompt }, sid);
  await sleep(400);
  // 优先点发送按钮；旧版 UI 没有按钮时回退到回车
  const clicked = await ev(`(()=>{const b=[...document.querySelectorAll('button')].find(b=>{const a=(b.getAttribute('aria-label')||'')+' '+(b.title||''); return /发送|Send|提交/.test(a)});if(b){b.click();return true}return false})()`);
  if (!clicked) {
    await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 }, sid);
    await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 }, sid);
  }

  // 等回复稳定（5s 无变化；最多等 180s）；只取最内层匹配元素，避免嵌套容器重复
  const GET = `(()=>{const els=[...document.querySelectorAll(${JSON.stringify(RESP)})];` +
    `const inner=els.filter(e=>!els.some(o=>o!==e&&e.contains(o)));` +
    `return inner.map(e=>e.innerText.trim()).filter(Boolean).join(String.fromCharCode(10)+String.fromCharCode(10))})()`;
  let last = '', stable = 0;
  for (let i = 0; i < 180; i++) {
    await sleep(1000);
    const cur = await ev(GET);
    if (cur && cur === last) { stable++; if (stable >= 5) break; } else { stable = 0; last = cur; }
  }
  process.stdout.write(last || '');
  if (fresh) {
    try { await send('Target.closeTarget', { targetId: page.targetId }); } catch (e) {}
    try { fs.unlinkSync(TARGET_FILE); } catch (e) {}
  }
  ws.close(); process.exit(0);
})().catch(e => { process.stderr.write(String(e) + '\n'); process.exit(1); });
