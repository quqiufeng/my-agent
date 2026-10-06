// operator/tools/weibo_fetch.js — 用「已登录的 Chrome」(CDP 9222) 打开一个微博页面，
// 抽出帖子里的图片 URL 并转成大图。纯 node（opencode 自身运行时），不依赖 Python。
// 用法: node weibo_fetch.js "<url>"
const fs = require('fs');

const portfile = process.env.HOME + '/.config/google-chrome/DevToolsActivePort';
const [port, bpath] = fs.readFileSync(portfile, 'utf8').trim().split('\n');
const ws = new WebSocket('ws://127.0.0.1:' + port + bpath);
let id = 0; const pend = {};
const send = (method, params, sessionId) => new Promise((res, rej) => {
    const i = ++id; pend[i] = { res, rej };
    ws.send(JSON.stringify({ id: i, method, params, sessionId }));
});
ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id && pend[m.id]) { m.error ? pend[m.id].rej(m.error) : pend[m.id].res(m.result); delete pend[m.id]; }
};

const url = process.argv[2];
const EVAL = `(()=>{
  const out=new Set();
  const big=u=>{
    if(!u) return null;
    if(u.startsWith('//')) u='https:'+u;
    if(!/wx\\d*\\.sinaimg\\.cn/.test(u)) return null;
    return u.replace(/\\/(orj360|orj480|thumb150|thumb180|thumbnail|mw690|small|wap360|bmiddle|orj\\d+)\\//,'/large/').replace(/\\?.*$/,'');
  };
  // ① 首选：九宫格里每个格子 li[action-type=fl_pics] 的缩略图 → 换大图（按格子顺序）
  document.querySelectorAll('li[action-type="fl_pics"] img').forEach(im=>{
    const u=big(im.currentSrc||im.src||im.getAttribute('data-src')||''); if(u) out.add(u);
  });
  // ② 兜底1：整个图片网格 [node-type=fl_pic_list] 内的 img
  if(out.size===0) document.querySelectorAll('[node-type="fl_pic_list"] img').forEach(im=>{
    const u=big(im.src||im.getAttribute('data-src')||''); if(u) out.add(u);
  });
  // ③ 兜底2：用 action-data 里的 pic_ids 直接拼大图
  if(out.size===0) document.querySelectorAll('[node-type="fl_pic_list"]').forEach(el=>{
    const m=(el.getAttribute('action-data')||'').match(/pic_ids=([^&]*)/);
    if(m&&m[1]) m[1].split(',').forEach(id=>{ if(id) out.add('https://wx1.sinaimg.cn/large/'+id+'.jpg'); });
  });
  return Array.from(out);
})()`;

(async () => {
    await new Promise(r => ws.onopen = r);
    const t = await send('Target.getTargets', {});
    let page = (t.targetInfos || []).find(x => x.type === 'page' && /s\.weibo\.com\/weibo/.test(x.url));
    let targetId = page ? page.targetId
        : (await send('Target.createTarget', { url: 'about:blank' })).targetId;
    const sessionId = (await send('Target.attachToTarget', { targetId, flatten: true })).sessionId;
    await send('Page.enable', {}, sessionId);
    await send('Page.navigate', { url }, sessionId);
    await new Promise(r => setTimeout(r, 6500));
    const r = await send('Runtime.evaluate', { expression: EVAL, returnByValue: true }, sessionId);
    const arr = (r.result && r.result.value) || [];
    console.log(arr.join('\n'));
    ws.close();
    process.exit(0);
})().catch(e => { console.error('ERR', e.message || JSON.stringify(e)); process.exit(1); });
