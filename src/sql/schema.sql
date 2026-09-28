-- The following file is used to generate the tables 
-- for the palacio language learning platform.

-- A conversation is a group of messages, where messages can 
-- branch off into distinct "branches". The "branches" are determined
-- by a concept we call "message coloring". It's described in further detail 
-- the "message_color" table.
--
-- The `next_available_color` field holds the color to be used on the  next 
-- message fork, for this conversation.
CREATE TABLE IF NOT EXISTS convo (
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  next_available_color INT DEFAULT 0,

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);

-- A message is really just some text representing a person
-- in a conversation. Messages reference the conversation that
-- they belong to, and their immediate parent. When a message is
-- added to a conversation, it's color is updated in the 
-- message color table.
CREATE TABLE IF NOT EXISTS message (
  content TEXT NOT NULL,
  conversation_id INT REFERENCES convo(id) ON DELETE CASCADE NOT NULL,
  role VARCHAR(256) DEFAULT 'person',
  parent_message_id INT REFERENCES message(id) ON DELETE CASCADE,

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);

-- The point of this app is to translate messages as a means for
-- creating comprehensible input. A translation is a version of the 
-- original message translated into a target language. At the moment,
-- a translation only references the message it is a translation of.
CREATE TABLE IF NOT EXISTS translation (
  content TEXT NOT NULL,
  language_enum VARCHAR(8) NOT NULL,
  message_id INT REFERENCES message(id) ON DELETE CASCADE,

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);

-- The message color concept is used to efficiently pull all the messages
-- in a given conversation branch. When a message is "forked" from the current
-- branch, by creating a new variation, the new branch is given a unique "color" (int),
-- and the parent messages also gain this new "color" as an entry in the message_color
-- table. 
--
-- Pulling a "branch" and all it's messages then turns into going to the leaf node, getting it's color,
-- and querying for messages containing that color.
CREATE TABLE IF NOT EXISTS message_color(
  message_id INT REFERENCES message(id) ON DELETE CASCADE,
  conversation_id INT REFERENCES convo(id) ON DELETE CASCADE,
  color INT,

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (message_id, conversation_id, color)
);
