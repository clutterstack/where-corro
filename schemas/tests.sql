-- Replace or add to existing schema
CREATE TABLE node_messages (
  pk TEXT PRIMARY KEY NOT NULL DEFAULT '',          -- Keep pk for consistency with existing pattern
  node_id TEXT NOT NULL DEFAULT '',        -- Same as pk but clearer
  message TEXT NOT NULL DEFAULT '',        -- Timestamp as message
  sequence INTEGER NOT NULL DEFAULT 0,    -- Message counter
  timestamp TEXT NOT NULL DEFAULT 0      -- ISO8601 timestamp
);

CREATE TABLE acknowledgments (
  id TEXT PRIMARY KEY,
  sender_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  receiver_id TEXT NOT NULL,
  received_at TEXT NOT NULL,
  acknowledged_at TEXT,
  ack_attempts INTEGER DEFAULT 0,
  ack_status TEXT DEFAULT 'pending'
);

