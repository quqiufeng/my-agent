// agentkit/tools/cdpc.js — 极简 CDP 守护客户端：把一行 JSON 发给本机 cdpd(9333)，打印响应
// 用法: node cdpc.js '{"cmd":"eval","args":{"js":"1+1"}}'
const net = require('net');
const req = process.argv[2] || '';
const sock = net.connect(9333, '127.0.0.1', () => sock.write(req + '\n'));
let buf = '';
sock.on('data', d => buf += d);
sock.on('error', () => process.exit(2));
sock.on('end', () => {
  try {
    const r = JSON.parse(buf.trim());
    if (r.ok) process.stdout.write(typeof r.out === 'string' ? r.out : JSON.stringify(r.out));
    else { process.stderr.write(r.err || 'err'); process.exit(1); }
  } catch (e) { process.exit(1); }
  process.exit(0);
});
