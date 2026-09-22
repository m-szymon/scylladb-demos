-- Substring search demo. Run after schema.cql and data.cql, once ./wait-for-indexes.sh reports both
-- indexes SERVING. Paste the queries one at a time into cqlsh, or run the whole file with
--   podman-compose exec scylla cqlsh -f /demo/demo.cql
--
-- The one thing to know: a column with a substring_index answers
--   WHERE column LIKE '%keyword%' LIMIT n
-- from the index, without ALLOW FILTERING and without a scan. Only that shape of pattern is served:
-- a literal keyword between two %, no other wildcard. Everything else LIKE can do still works the
-- way it always did, with ALLOW FILTERING.

-- ---------------------------------------------------------------------------------------------
-- 0. The data: seventeen accounts, and the two indexes.
-- ---------------------------------------------------------------------------------------------
SELECT nickname, username, register_time, status FROM search_demo.users;

DESCRIBE INDEX search_demo.users_nickname_sub;

-- ---------------------------------------------------------------------------------------------
-- 1. Containment. Five nicknames contain 将军, at the start, in the middle and at the end.
--    Before this index the same question needed ALLOW FILTERING and read the whole table.
-- ---------------------------------------------------------------------------------------------
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 20;

-- One character is a keyword too: every nickname with 将, including 将领.
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将%' LIMIT 20;

-- ---------------------------------------------------------------------------------------------
-- 2. It is a substring, not a bag of characters: 南宫 finds 南宫月 and 小南宫粉丝团, not 宫南.
-- ---------------------------------------------------------------------------------------------
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%南宫%' LIMIT 20;

-- 宫 alone finds all three.
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%宫%' LIMIT 20;

-- ---------------------------------------------------------------------------------------------
-- 3. Latin is matched case-insensitively (case_sensitive = 'false' on both indexes):
--    ng, NG and Ng are the same search, and NGgamer, kingNG and jiangjunlaile all contain it.
-- ---------------------------------------------------------------------------------------------
SELECT username, nickname FROM search_demo.users WHERE username LIKE '%ng%' LIMIT 20;
SELECT username, nickname FROM search_demo.users WHERE username LIKE '%NG%' LIMIT 20;
SELECT username, nickname FROM search_demo.users WHERE username LIKE '%Ng%' LIMIT 20;

-- The same for the Latin part of a nickname.
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%ng%' LIMIT 20;

-- ---------------------------------------------------------------------------------------------
-- 4. Digits are characters like any other: 925555 is inside 925555 and 9255551, not 925.
-- ---------------------------------------------------------------------------------------------
SELECT username, nickname FROM search_demo.users WHERE username LIKE '%925555%' LIMIT 20;
SELECT username, nickname FROM search_demo.users WHERE username LIKE '%925%'    LIMIT 20;

-- ---------------------------------------------------------------------------------------------
-- 5. Keywords longer than max_gram (3 by default). The index holds substrings of up to three
--    characters; a longer keyword is answered by intersecting its three-character pieces and
--    checking the candidates against the stored text, so it is exact all the same.
-- ---------------------------------------------------------------------------------------------
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军来了%'   LIMIT 20;
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%南宫粉丝团%' LIMIT 20;
SELECT username, nickname FROM search_demo.users WHERE username LIKE '%jiangjun%'   LIMIT 20;

-- A keyword nobody has.
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军来啦%' LIMIT 20;

-- ---------------------------------------------------------------------------------------------
-- 6. LIMIT is what the search box asks for: the index stops after that many matches.
--    Which two of the five come back is up to the index; there is no ordering in this stage.
-- ---------------------------------------------------------------------------------------------
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 2;

-- ---------------------------------------------------------------------------------------------
-- 7. Names change. The index follows the table through CDC within a second or two: a renamed
--    account is found under its new name, a deleted one disappears, a new one appears.
--    (Running the file in one go, the SELECTs may be a moment too early; repeat them.)
-- ---------------------------------------------------------------------------------------------
UPDATE search_demo.users SET nickname = '大元帅' WHERE user_id = 2cfbb005-a436-44e4-aae1-7ba1d5c9427d;
DELETE FROM search_demo.users WHERE user_id = b2203663-516f-4118-a6fb-dc696a9cca73;
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username)
  VALUES (0fcde168-fffa-41b0-a08c-2664b9faec1e, 0, '新将军', '2024-08-01T00:00:00+0000', 0, 'newgeneral');

SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%大元帅%' LIMIT 20;
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%司令%'   LIMIT 20;
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%'   LIMIT 20;

-- Put the data back so that the demo can be run again.
UPDATE search_demo.users SET nickname = '元帅' WHERE user_id = 2cfbb005-a436-44e4-aae1-7ba1d5c9427d;
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username)
  VALUES (b2203663-516f-4118-a6fb-dc696a9cca73, 0, '司令', '2024-01-07T00:00:00+0000', 0, 'user0006');
DELETE FROM search_demo.users WHERE user_id = 0fcde168-fffa-41b0-a08c-2664b9faec1e;

-- ---------------------------------------------------------------------------------------------
-- 8. Guard rails: what the index does not serve, and what happens then.
-- ---------------------------------------------------------------------------------------------
-- A prefix pattern is not containment. The index steps aside and LIKE behaves as before:
-- ALLOW FILTERING is required...
SELECT nickname FROM search_demo.users WHERE nickname LIKE '将军%' LIMIT 20;

-- ...and with it the query runs as a filtered scan, exactly as on a table without the index.
SELECT nickname FROM search_demo.users WHERE nickname LIKE '将军%' LIMIT 20 ALLOW FILTERING;

-- The same for a pattern with a single-character wildcard inside the keyword.
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将_来%' LIMIT 20;

-- A containment query needs a LIMIT, of at most 1000.
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%';
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 1001;

-- It is one LIKE on the indexed column and nothing else: no second restriction, no ORDER BY.
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' AND status = 0 LIMIT 20;
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' AND username LIKE '%user%' LIMIT 20;
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' ORDER BY register_time DESC LIMIT 20;

-- A known limit of this stage: the index is chosen as soon as the LIKE fits it, ALLOW FILTERING
-- or not, so a containment LIKE mixed with another restriction is rejected rather than run as a
-- filtered scan. Falling back to the scan in that case is the natural next step.
SELECT nickname FROM search_demo.users WHERE account_type = 0 AND nickname LIKE '%将军%' LIMIT 20 ALLOW FILTERING;
