CREATE TABLE acknowledgments (
  id TEXT PRIMARY KEY NOT NULL DEFAULT 'tbd',
  sender_id TEXT NOT NULL DEFAULT 'no_id',
  sequence INTEGER NOT NULL DEFAULT 0,
  receiver_id TEXT NOT NULL DEFAULT 'empty',
  received_at TEXT NOT NULL DEFAULT 'empty',
  acknowledged_at TEXT DEFAULT 'tbd',
  ack_attempts INTEGER DEFAULT 0,
  ack_status TEXT DEFAULT 'pending'
);

