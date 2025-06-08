CREATE TABLE propagation_metrics (
  id TEXT PRIMARY KEY NOT NULL DEFAULT '',
  sender_id TEXT NOT NULL DEFAULT '',
  sequence INTEGER NOT NULL DEFAULT 0,
  sent_at TEXT NOT NULL DEFAULT '',
  topology_id TEXT NOT NULL DEFAULT 'default',
  metrics TEXT NOT NULL DEFAULT '{}'
);