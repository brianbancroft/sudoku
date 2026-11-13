CREATE TABLE packs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  summary TEXT NOT NULL,
  difficulty_mix TEXT NOT NULL,
  product_id TEXT NOT NULL UNIQUE,
  available INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE puzzles (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL REFERENCES packs(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  givens TEXT NOT NULL,
  solution TEXT NOT NULL,
  difficulty TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  UNIQUE (pack_id, sort_order)
);

CREATE TABLE entitlements (
  original_transaction_id TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  bundle_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  device_ids TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE admin_users (
  email TEXT PRIMARY KEY,
  last_login_at TEXT NOT NULL
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  csrf TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE TABLE oauth_states (
  state TEXT PRIMARY KEY,
  nonce TEXT NOT NULL,
  provider TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
