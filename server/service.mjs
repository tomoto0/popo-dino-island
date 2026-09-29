import { createHash, randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
// Username/password accounts and one cloud save slot per account.
// Passwords are stored only as salted scrypt hashes; session tokens only as SHA-256 hashes.
const scrypt = promisify(scryptCallback);
export const fail = (status, code, extra = {}) => { throw Object.assign(new Error(code), { status, code, extra }); };
export const USERNAME_PATTERN = /^[A-Za-z0-9_]{3,16}$/;
export const PASSWORD_PATTERN = /^[\x21-\x7e]{6,64}$/;
export const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
export const SESSION_SECONDS = 180 * 24 * 60 * 60;
export const MAX_SAVE_BYTES = 32 * 1024;
const SCRYPT = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };
const KEY_BYTES = 32;
const sha256 = value => createHash('sha256').update(value).digest('hex');
export async function hashPassword(password) {
  const salt = randomBytes(16);
  const key = await scrypt(password, salt, KEY_BYTES, SCRYPT);
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString('base64url')}$${key.toString('base64url')}`;
}
export async function verifyPassword(password, stored) {
  const parts = String(stored || '').split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, n, r, p, saltText, keyText] = parts;
  const expected = Buffer.from(keyText, 'base64url');
  const actual = await scrypt(password, Buffer.from(saltText, 'base64url'), expected.length, { N: Number(n), r: Number(r), p: Number(p), maxmem: SCRYPT.maxmem });
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}
// A fixed dummy hash keeps unknown-user logins on the same scrypt cost as real ones.
const DUMMY_HASH = 'scrypt$16384$8$1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
function credentials(input) {
  const username = typeof input.username === 'string' ? input.username.trim() : '';
  const password = typeof input.password === 'string' ? input.password : '';
  return { username, password, key: username.toLowerCase() };
}
export function createSaveService(db, namespace = 'production') {
  async function rateLimit(bucket, limit, windowSeconds, code = 'rate_limited') {
    const hash = sha256(`${namespace}:${bucket}`);
    // request_count is assigned first so it still reads the previous window_start.
    await db.execute(`INSERT INTO yoshi_rate_limits (bucket_hash,window_start,request_count) VALUES (?,NOW(3),1)
      ON DUPLICATE KEY UPDATE
        request_count = IF(window_start < NOW(3) - INTERVAL ? SECOND, 1, request_count + 1),
        window_start = IF(window_start < NOW(3) - INTERVAL ? SECOND, NOW(3), window_start)`, [hash, windowSeconds, windowSeconds]);
    const [[row]] = await db.execute('SELECT request_count FROM yoshi_rate_limits WHERE bucket_hash=?', [hash]);
    if (Number(row?.request_count || 0) > limit) fail(429, code);
  }
  async function createSession(account) {
    const token = randomBytes(32).toString('base64url');
    await db.execute('INSERT INTO yoshi_sessions (token_hash,account_id,expires_at) VALUES (?,?,NOW(3) + INTERVAL ? SECOND)', [sha256(token), account.id, SESSION_SECONDS]);
    return { token, username: account.username, expiresInSeconds: SESSION_SECONDS };
  }
  return {
    async register(input) {
      const { username, password, key } = credentials(input);
      if (!USERNAME_PATTERN.test(username)) fail(400, 'invalid_username');
      if (!PASSWORD_PATTERN.test(password)) fail(400, 'invalid_password');
      await rateLimit('register:all', 300, 60, 'registration_busy');
      const passwordHash = await hashPassword(password);
      let id;
      try {
        const [result] = await db.execute('INSERT INTO yoshi_accounts (username_key,username,password_hash,last_login_at) VALUES (?,?,?,NOW(3))', [key, username, passwordHash]);
        id = Number(result.insertId);
      } catch (error) {
        if (error?.code === 'ER_DUP_ENTRY' || error?.errno === 1062) fail(409, 'username_taken');
        throw error;
      }
      return createSession({ id, username });
    },
    async login(input) {
      const { username, password, key } = credentials(input);
      if (!USERNAME_PATTERN.test(username) || !PASSWORD_PATTERN.test(password)) fail(401, 'invalid_credentials');
      await rateLimit(`login:${key}`, 12, 600, 'too_many_attempts');
      const [[account]] = await db.execute('SELECT id,username,password_hash FROM yoshi_accounts WHERE username_key=?', [key]);
      const valid = await verifyPassword(password, account?.password_hash || DUMMY_HASH);
      if (!account || !valid) fail(401, 'invalid_credentials');
      await db.execute('UPDATE yoshi_accounts SET last_login_at=NOW(3) WHERE id=?', [account.id]);
      await db.execute('DELETE FROM yoshi_sessions WHERE account_id=? AND expires_at < NOW(3)', [account.id]);
      return createSession({ id: Number(account.id), username: account.username });
    },
    async identity(token) {
      if (typeof token !== 'string' || !TOKEN_PATTERN.test(token)) fail(401, 'session_invalid');
      const [[row]] = await db.execute(`SELECT a.id,a.username FROM yoshi_sessions s JOIN yoshi_accounts a ON a.id=s.account_id
        WHERE s.token_hash=? AND s.expires_at > NOW(3)`, [sha256(token)]);
      if (!row) fail(401, 'session_invalid');
      return { id: Number(row.id), username: row.username, tokenHash: sha256(token) };
    },
    async logout(account) {
      await db.execute('DELETE FROM yoshi_sessions WHERE token_hash=?', [account.tokenHash]);
      return { ok: true };
    },
    async readSave(account) {
      const [[row]] = await db.execute('SELECT revision,save_data,updated_at FROM yoshi_saves WHERE account_id=?', [account.id]);
      if (!row) return { username: account.username, revision: 0, data: null, updatedAt: null };
      let data = null;
      try { data = JSON.parse(row.save_data); } catch { data = null; }
      return { username: account.username, revision: Number(row.revision), data, updatedAt: row.updated_at };
    },
    async writeSave(account, input) {
      const revision = input.revision;
      if (!Number.isSafeInteger(revision) || revision < 0) fail(400, 'invalid_revision');
      if (!input.data || typeof input.data !== 'object' || Array.isArray(input.data)) fail(400, 'invalid_save');
      const encoded = JSON.stringify(input.data);
      if (Buffer.byteLength(encoded, 'utf8') > MAX_SAVE_BYTES) fail(413, 'save_too_large');
      await rateLimit(`save:${account.id}`, 90, 60);
      return db.transaction(async tx => {
        const [[row]] = await tx.execute('SELECT revision,save_data FROM yoshi_saves WHERE account_id=? FOR UPDATE', [account.id]);
        const current = row ? Number(row.revision) : 0;
        if (current !== revision) {
          let data = null;
          try { data = row ? JSON.parse(row.save_data) : null; } catch { data = null; }
          fail(409, 'save_conflict', { revision: current, data });
        }
        const next = current + 1;
        if (row) await tx.execute('UPDATE yoshi_saves SET revision=?,save_data=?,updated_at=NOW(3) WHERE account_id=?', [next, encoded, account.id]);
        else await tx.execute('INSERT INTO yoshi_saves (account_id,revision,save_data) VALUES (?,?,?)', [account.id, next, encoded]);
        return { revision: next };
      });
    },
  };
}
