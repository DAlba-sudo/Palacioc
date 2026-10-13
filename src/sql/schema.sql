-- Palacioc schema. Applied by the dev compose only on a fresh data volume.

-- A conversation is a tree of messages written in `source_language`.
CREATE TABLE IF NOT EXISTS conversation (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  source_language VARCHAR(35) NOT NULL DEFAULT 'en',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS conversation_created_idx ON conversation (created_at DESC);

-- A message has at most one parent (NULL = root; several roots are allowed), so
-- a conversation is a forest and a "route" is a root-to-message path. The
-- composite FK keeps a parent inside the same conversation. Deleting a message
-- deletes its whole subtree.
CREATE TABLE IF NOT EXISTS message (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  conversation_id INT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
  parent_message_id INT,
  role VARCHAR(64) NOT NULL DEFAULT 'person',
  content TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (id, conversation_id),
  FOREIGN KEY (parent_message_id, conversation_id)
    REFERENCES message(id, conversation_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS message_conversation_idx ON message (conversation_id);
CREATE INDEX IF NOT EXISTS message_parent_idx ON message (parent_message_id);

-- A translation of one message into `language` (BCP 47-style code); a message
-- may have several, including several in the same language.
CREATE TABLE IF NOT EXISTS translation (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  message_id INT NOT NULL REFERENCES message(id) ON DELETE CASCADE,
  language VARCHAR(35) NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS translation_message_idx ON translation (message_id);
