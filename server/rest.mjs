import { fail } from './service.mjs';
export const prefix = '/api/v1';
export const send = (res, status, data) => {
  if (res.destroyed || res.writableEnded) return;
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  res.end(JSON.stringify(data));
};
async function body(req, keys, maxBytes = 1024) {
  if (!String(req.headers['content-type'] || '').startsWith('application/json')) fail(415, 'json_required');
  const chunks = [];
  let bytes = 0;
  for await (const chunk of req) {
    bytes += chunk.length;
    if (bytes > maxBytes) fail(413, 'body_too_large');
    chunks.push(chunk);
  }
  let value;
  try { value = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { fail(400, 'invalid_json'); }
  if (!value || Array.isArray(value) || typeof value !== 'object' || Object.keys(value).some(key => !keys.includes(key))) fail(400, 'invalid_fields');
  return value;
}
// Preview ingress in older sandbox runtimes strips Authorization, so clients also send X-Session-Token.
function sessionToken(req) {
  const direct = req.headers['x-session-token'];
  if (typeof direct === 'string' && direct) return direct;
  const header = String(req.headers.authorization || '');
  return header.startsWith('Bearer ') ? header.slice(7) : '';
}
export function createSaveRest(service, { ready, check }) {
  return async function handle(req, res) {
    const url = new URL(req.url, 'http://game-api');
    if (!url.pathname.startsWith(`${prefix}/`)) fail(404, 'not_found');
    if (req.headers['sec-fetch-site'] === 'cross-site') fail(403, 'cross_origin_request');
    const route = url.pathname.slice(prefix.length);
    if (route === '/health' && req.method === 'GET') return send(res, 200, await ready());
    await check();
    if (req.method === 'POST' && route === '/auth/register') return send(res, 201, await service.register(await body(req, ['username', 'password'])));
    if (req.method === 'POST' && route === '/auth/login') return send(res, 200, await service.login(await body(req, ['username', 'password'])));
    const account = await service.identity(sessionToken(req));
    if (req.method === 'POST' && route === '/auth/logout') return send(res, 200, await service.logout(account));
    if (req.method === 'GET' && route === '/me') return send(res, 200, { username: account.username });
    if (req.method === 'GET' && route === '/save') return send(res, 200, await service.readSave(account));
    if (req.method === 'PUT' && route === '/save') return send(res, 200, await service.writeSave(account, await body(req, ['revision', 'data'], 40 * 1024)));
    fail(404, 'not_found');
  };
}
