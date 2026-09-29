import http from 'node:http';
import mysql from 'mysql2/promise';
import { readBackendContract } from './backend-contract.mjs';
import { createRequestDatabase, databaseStream, DATABASE_CONCURRENCY } from './request-database.mjs';
import { createSaveService } from './service.mjs';
import { createSaveRest, send } from './rest.mjs';
// This server belongs to the generated game (accounts + cloud saves), never to Addon Server.
export const PROTOCOL_VERSION = 1;
export const SCHEMA_VERSION = 1;
const backendContract = readBackendContract(process.cwd(), { required: true }).value;
if (backendContract.api.protocolVersion !== PROTOCOL_VERSION || backendContract.database.schemaVersion !== SCHEMA_VERSION || backendContract.deploy.healthPath !== '/api/health') throw new Error('backend_contract_incompatible');
const namespace = 'production';
if (!process.env.DATABASE_URL) throw new Error('Project DATABASE_URL is required');
const pool = mysql.createPool({ uri: process.env.DATABASE_URL, stream: databaseStream(process.env.DATABASE_URL), connectionLimit: DATABASE_CONCURRENCY, waitForConnections: false, connectTimeout: 3000, timezone: 'Z', dateStrings: true });
const db = createRequestDatabase(pool);
const unavailable = code => Object.assign(new Error(code), { status: 503, code });
async function check() {
  const [[environment]] = await db.execute('SELECT namespace,schema_version FROM yoshi_environment WHERE id=1');
  if (environment?.namespace !== namespace || Number(environment.schema_version) !== SCHEMA_VERSION) throw unavailable('database_environment_mismatch');
}
const handle = createSaveRest(createSaveService(db, namespace), {
  check,
  async ready() {
    await check();
    // LIMIT 0 validates every consumed column without reading player data.
    await db.execute('SELECT id,username_key,username,password_hash,created_at,last_login_at FROM yoshi_accounts LIMIT 0');
    await db.execute('SELECT token_hash,account_id,created_at,expires_at FROM yoshi_sessions LIMIT 0');
    await db.execute('SELECT account_id,revision,save_data,updated_at FROM yoshi_saves LIMIT 0');
    await db.execute('SELECT bucket_hash,window_start,request_count FROM yoshi_rate_limits LIMIT 0');
    return { status: 'ok', namespace, protocolVersion: PROTOCOL_VERSION, schemaVersion: SCHEMA_VERSION };
  },
});
const server = http.createServer((req, res) => {
  // Startup probes bypass database readiness and request admission.
  if (req.method === 'GET' && req.url?.split('?')[0] === '/api/health') return send(res, 200, { status: 'ok' });
  db.run(req, res, () => handle(req, res)).catch(error => {
    if (res.destroyed || res.writableEnded) return;
    if (!error.status) console.error('request_failed', error?.code || error?.message);
    send(res, error.status || 503, { error: error.code && error.status ? error.code : 'server_unavailable', ...(error.extra || {}) });
    if (!req.complete) res.once('finish', () => req.destroy());
  });
});
server.requestTimeout = 15_000;
server.headersTimeout = 10_000;
server.listen(Number(process.env.PORT || 8080), process.env.HOST || '0.0.0.0', () => {
  const address = server.address();
  if (typeof address === 'object') process.send?.({ type: 'ready', port: address.port });
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => pool.end().finally(() => process.exit(0))));
