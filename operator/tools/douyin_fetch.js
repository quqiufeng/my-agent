// operator/tools/douyin_fetch.js — 经已登录 Chrome(CDP) 取抖音登录 cookie + 我的作品列表
// 用法: node douyin_fetch.js <N>  → 写 /tmp/douyin_cookies.txt、/tmp/douyin_list.json，打印 sec_uid/count
const fs = require('fs');
const home = process.env.HOME;
const [port, bpath] = fs.readFileSync(home + '/.config/google-chrome/DevToolsActivePort', 'utf8').trim().split('\n');
const ws = new WebSocket('ws://127.0.0.1:' + port + bpath);
let id = 0, pend = {};
const send = (m, p, s) => new Promise((res, rej) => { const i = ++id; pend[i] = { res, rej }; ws.send(JSON.stringify({ id: i, method: m, params: p, sessionId: s })); });
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend[m.id]) { m.error ? pend[m.id].rej(m.error) : pend[m.id].res(m.result); delete pend[m.id]; } };
const COUNT = Math.max(1, parseInt(process.argv[2] || '18', 10));
const SEC_ARG = (process.argv[3] || '').trim();  // 指定用户 sec_uid（留空=自己）

(async () => {
  await new Promise(r => ws.onopen = r);
  const t = await send('Target.createTarget', { url: 'about:blank' });
  const sid = (await send('Target.attachToTarget', { targetId: t.targetId, flatten: true })).sessionId;
  await send('Page.enable', {}, sid);
  await send('Network.enable', {}, sid);
  await send('Page.navigate', { url: 'https://www.douyin.com/user/self' }, sid);
  await new Promise(r => setTimeout(r, 9000));

  const ck = await send('Network.getAllCookies', {}, sid);
  const cookies = (ck.cookies || []).filter(c => /douyin|bytedance|snssdk|toutiao/.test(c.domain));
  let out = '# Netscape HTTP Cookie File\n';
  for (const c of cookies) {
    const exp = Math.floor(c.expires || 0);
    out += [c.domain, (c.domain.startsWith('.') ? 'TRUE' : 'FALSE'), c.path, (c.secure ? 'TRUE' : 'FALSE'), exp > 0 ? exp : 0, c.name, c.value].join('\t') + '\n';
  }
  fs.writeFileSync(home + '/.myagent_douyin_cookie', out);

  let sec = SEC_ARG;
  if (!sec) {
    const selfExpr = `(async()=>{try{const r=await fetch('/aweme/v1/web/user/profile/self/?device_platform=webapp&aid=6383&channel=channel_pc_web&source=channel_pc_web',{credentials:'include'});const j=await r.json();return (j.user&&j.user.sec_uid)||'';}catch(e){return ''}})()`;
    const secr = await send('Runtime.evaluate', { expression: selfExpr, awaitPromise: true, returnByValue: true }, sid);
    sec = secr.result.value || '';
    if (!sec) { console.error('NO_LOGIN: Chrome 未登录抖音，且未指定 uid'); process.exit(2); }
  }

  const fetchExpr = (cursor) => `(async()=>{try{const r=await fetch('/aweme/v1/web/aweme/post/?device_platform=webapp&aid=6383&channel=channel_pc_web&sec_user_id=${sec}&max_cursor=${cursor}&locate_query=false&count=18&publish_video_strategy_type=2&version_code=170400&version_name=17.4.0&cookie_enabled=true&platform=PC&browser_language=zh-CN&browser_platform=Win32&browser_name=Chrome&browser_version=124.0.0.0&browser_online=true',{credentials:'include'});const j=await r.json();return JSON.stringify({has_more:j.has_more,max_cursor:j.max_cursor,list:(j.aweme_list||[]).map(a=>({id:String(a.aweme_id),desc:a.desc||'',digg:(a.statistics||{}).digg_count||0,url:(((a.video||{}).play_addr||{}).url_list||[])[0]||''}))});}catch(e){return JSON.stringify({err:e.message})}})()`;

  let all = [], cursor = 0, guard = 0;
  while (all.length < COUNT && guard++ < 30) {
    const rr = await send('Runtime.evaluate', { expression: fetchExpr(cursor), awaitPromise: true, returnByValue: true }, sid);
    let j = {}; try { j = JSON.parse(rr.result.value); } catch (e) { break; }
    if (j.err) break;
    all = all.concat(j.list || []);
    if (!j.has_more || !(j.list || []).length) break;
    cursor = j.max_cursor;
  }
  all = all.slice(0, COUNT).map((a, i) => ({ i: i + 1, id: a.id, digg: a.digg, desc: a.desc, url: a.url }));
  fs.writeFileSync('/tmp/douyin_list.json', JSON.stringify(all));
  fs.writeFileSync('/tmp/douyin_sec.txt', sec);
  console.log('sec_uid=' + sec + ' count=' + all.length + ' cookies=' + cookies.length);
  ws.close(); process.exit(0);
})().catch(e => { console.error('ERR', (e && e.message) || e); process.exit(1); });
