// Integration test for the save API against the project database.
// Usage (project root): node server/test/api-smoke.mjs
// Creates one uniquely named test account and deletes it (and its sessions/save) afterwards.
import { fork } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import mysql from 'mysql2/promise';
const root = dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const port = 18080 + Math.floor(Math.random() * 1000);
const child = fork(join(root, 'server/server.mjs'), [], { cwd: root, env: { ...process.env, PORT: String(port), HOST: '127.0.0.1' }, stdio: 'inherit' });
await new Promise((resolve, reject) => { child.once('message', resolve); child.once('exit', code => reject(new Error(`server exited ${code}`))); });
const base = `http://127.0.0.1:${port}/api`;
const call = async (method, path, body, token) => {
  const headers = { Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) { headers['X-Session-Token'] = token; headers.Authorization = `Bearer ${token}`; }
  const response = await fetch(base + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: response.status, data: await response.json() };
};
const username = `zt_${Math.random().toString(36).slice(2, 10)}`;
const password = 'egg-pass-123';
let failed = false;
try {
  assert.equal((await call('GET', '/health')).status, 200);
  const ready = await call('GET', '/v1/health');
  assert.equal(ready.status, 200, JSON.stringify(ready.data));
  assert.equal((await call('POST', '/v1/auth/register', { username: 'a', password })).data.error, 'invalid_username');
  assert.equal((await call('POST', '/v1/auth/register', { username, password: '123' })).data.error, 'invalid_password');
  const registered = await call('POST', '/v1/auth/register', { username, password });
  assert.equal(registered.status, 201, JSON.stringify(registered.data));
  assert.match(registered.data.token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal((await call('POST', '/v1/auth/register', { username: username.toUpperCase(), password })).data.error, 'username_taken');
  const empty = await call('GET', '/v1/save', undefined, registered.data.token);
  assert.deepEqual([empty.status, empty.data.revision, empty.data.data], [200, 0, null]);
  const saved = await call('PUT', '/v1/save', { revision: 0, data: { version: 1, lives: 5, cleared: { '1-1': { score: 1200 } } } }, registered.data.token);
  assert.deepEqual([saved.status, saved.data.revision], [200, 1]);
  const conflict = await call('PUT', '/v1/save', { revision: 0, data: { version: 1 } }, registered.data.token);
  assert.equal(conflict.status, 409);
  assert.equal(conflict.data.error, 'save_conflict');
  assert.equal(conflict.data.revision, 1);
  assert.equal(conflict.data.data.lives, 5);
  assert.equal((await call('POST', '/v1/auth/login', { username, password: 'wrong-pass' })).status, 401);
  const login = await call('POST', '/v1/auth/login', { username: username.toUpperCase(), password });
  assert.equal(login.status, 200, JSON.stringify(login.data));
  const loaded = await call('GET', '/v1/save', undefined, login.data.token);
  assert.equal(loaded.data.data.cleared['1-1'].score, 1200);
  assert.equal((await call('GET', '/v1/me', undefined, login.data.token)).data.username, username);
  assert.equal((await call('POST', '/v1/auth/logout', {}, login.data.token)).status, 200);
  assert.equal((await call('GET', '/v1/save', undefined, login.data.token)).status, 401);
  assert.equal((await call('GET', '/v1/save', undefined, 'x'.repeat(43))).status, 401);
  console.log('[API_PASS] register, validation, duplicate, save, conflict, login, logout verified');
} catch (error) {
  failed = true;
  console.error('[API_FAIL]', error.message);
} finally {
  const connection = await mysql.createConnection({ uri: process.env.DATABASE_URL });
  const [[account]] = await connection.execute('SELECT id FROM yoshi_accounts WHERE username_key=?', [username.toLowerCase()]);
  if (account) {
    await connection.execute('DELETE FROM yoshi_sessions WHERE account_id=?', [account.id]);
    await connection.execute('DELETE FROM yoshi_saves WHERE account_id=?', [account.id]);
    await connection.execute('DELETE FROM yoshi_accounts WHERE id=?', [account.id]);
  }
  await connection.end();
  child.kill('SIGTERM');
  process.exitCode = failed ? 1 : 0;
}
