// Loopback-only HTTP fixture for the isolated ArkWeb UI checks.
const http = require('node:http');
let failing = false;
http.createServer((req, res) => {
  console.log(JSON.stringify({ time: new Date().toISOString(), path: req.url, failing }));
  if (req.url === '/admin/fail/on' || req.url === '/admin/fail/off') {
    failing = req.url.endsWith('/on');
    res.end('ok');
    return;
  }
  if (failing) { req.socket.destroy(); return; }
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(req.url === '/two'
    ? '<!doctype html><html><head><title>HiSH page two</title></head><body><h1>HiSH page two</h1></body></html>'
    : '<!doctype html><html><head><title>HiSH page one</title></head><body><h1>HiSH page one</h1><a href="/two">Next page</a></body></html>');
}).listen(18085, '127.0.0.1', () => console.log('READY'));
