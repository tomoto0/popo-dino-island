-- Yoshi Island Adventure: username/password accounts and cloud saves.
-- Applied explicitly with `npm --prefix server run db:migrate` before the first dependent checkpoint.
-- Additive only: keep these tables when rolling code back.
CREATE TABLE IF NOT EXISTS yoshi_accounts (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 username_key VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 username VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 password_hash VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 last_login_at DATETIME(3) NULL,
 UNIQUE KEY yoshi_accounts_username_key (username_key)
);
CREATE TABLE IF NOT EXISTS yoshi_sessions (
 token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
 account_id BIGINT UNSIGNED NOT NULL,
 created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 expires_at DATETIME(3) NOT NULL,
 KEY yoshi_sessions_account (account_id),
 KEY yoshi_sessions_expiry (expires_at)
);
CREATE TABLE IF NOT EXISTS yoshi_saves (
 account_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
 revision INT UNSIGNED NOT NULL,
 save_data MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
 updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
);
CREATE TABLE IF NOT EXISTS yoshi_rate_limits (
 bucket_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
 window_start DATETIME(3) NOT NULL,
 request_count INT UNSIGNED NOT NULL
);
CREATE TABLE IF NOT EXISTS yoshi_environment (
 id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
 namespace VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 schema_version INT UNSIGNED NOT NULL
);
INSERT IGNORE INTO yoshi_environment (id,namespace,schema_version) VALUES (1,'production',1);
