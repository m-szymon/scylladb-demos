-- Substring search demo: schema.
-- One table of accounts with two searchable text columns, one substring index on each, so that the
-- search box of a live-streaming site can find an account by any part of its nickname or username.

CREATE KEYSPACE IF NOT EXISTS search_demo
  WITH replication = {'class': 'NetworkTopologyStrategy', 'replication_factor': 1}
  AND tablets = {'enabled': true};

CREATE TABLE IF NOT EXISTS search_demo.users (
  user_id       uuid PRIMARY KEY,
  account_type  int,
  nickname      text,        -- display name, mostly CJK, 1-32 characters
  register_time timestamp,
  status        int,         -- 0 = active, 1 = banned
  username      text         -- login name, Latin letters and digits
);

-- Substring indexes. The Vector Store indexes every substring of min_gram..max_gram characters of
-- the column (defaults 1..3); a LIKE '%keyword%' on the column is then answered from the index.
-- CQL LIKE is case-sensitive; case_sensitive = 'false' makes both the index and the keyword
-- lowercase, which is what a search box wants for Latin names.
CREATE CUSTOM INDEX IF NOT EXISTS users_nickname_sub ON search_demo.users (nickname)
  USING 'substring_index'
  WITH OPTIONS = {'case_sensitive': 'false'};

CREATE CUSTOM INDEX IF NOT EXISTS users_username_sub ON search_demo.users (username)
  USING 'substring_index'
  WITH OPTIONS = {'case_sensitive': 'false'};
