-- Substring search demo. Run after schema.cql and data.cql, once ./wait-for-indexes.sh reports the
-- three indexes SERVING. Paste the queries one at a time into cqlsh, or run the whole file with
--   podman-compose exec scylla cqlsh -f /demo/demo.cql
--
-- The one thing to know: a column with a pattern_index answers
--   WHERE column LIKE '%keyword%'
-- from the index, without ALLOW FILTERING and without a scan, a page at a time.
--
-- An index answers in one order, and a query goes to the index whose order fits it. The nickname
-- column has two indexes: one with no order_by, which serves a LIKE with no ORDER BY, and one
-- ordered by register_time, which serves
--   WHERE nickname LIKE '%keyword%' AND register_time < t ORDER BY register_time DESC
-- -- a search box that shows the newest matches first, with a date filter. Sections 6a to 6c
-- are that.

-- ---------------------------------------------------------------------------------------------
-- 0. The data: seventeen accounts, and one of the three indexes.
-- ---------------------------------------------------------------------------------------------
SELECT nickname, username, register_time, status FROM search_demo.users;

DESCRIBE INDEX search_demo.users_nickname_newest;

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
--    Without ORDER BY they are the first two in the index's own order, which is fixed but means
--    nothing: a query that cares which two it gets says ORDER BY (6a).
-- ---------------------------------------------------------------------------------------------
SELECT nickname, register_time FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 2;

-- ---------------------------------------------------------------------------------------------
-- 6a. ORDER BY. This query goes to the other nickname index, the one ordered by register_time.
--     It walks its matches newest first, so the order is global, not a re-sort of one page.
-- ---------------------------------------------------------------------------------------------
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%' ORDER BY register_time DESC LIMIT 20;

-- Either direction: the reverse is the same walk from the other end. Ordering by a column no
-- index on nickname is ordered by is refused rather than answered in the wrong order.
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' ORDER BY register_time ASC LIMIT 20;
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' ORDER BY user_id DESC LIMIT 20;

-- ---------------------------------------------------------------------------------------------
-- 6b. A range on the ordered column. The date filter of the search box: it is pushed down to the
--     index, which never looks at the excluded rows, rather than filtered out afterwards.
-- ---------------------------------------------------------------------------------------------
-- The 将军 accounts registered before March: 李将军 and 宇将军.
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%' AND register_time < '2024-03-01T00:00:00+0000'
  ORDER BY register_time DESC LIMIT 20;

-- Between two dates. Both bounds go down to the index.
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%'
    AND register_time >= '2024-02-01T00:00:00+0000'
    AND register_time <= '2024-07-01T00:00:00+0000'
  ORDER BY register_time DESC LIMIT 20;

-- ---------------------------------------------------------------------------------------------
-- 6c. Paging. Each page tells the index where the last one stopped, so page 5 costs what page 1
--     costs -- the walk resumes rather than restarting and skipping. The five 将军 accounts come
--     back two at a time, in one order, with no row repeated and none missed.
-- ---------------------------------------------------------------------------------------------
PAGING 2;
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%' ORDER BY register_time DESC LIMIT 20;
PAGING OFF;

-- The LIMIT bounds the whole query, not the page: three rows, over two pages.
PAGING 2;
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%' ORDER BY register_time DESC LIMIT 3;
PAGING OFF;

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
-- 8. Guard rails: what a query on an indexed column may ask, and what happens when it asks more.
-- ---------------------------------------------------------------------------------------------
-- Every LIKE on an indexed column goes to the index, ALLOW FILTERING or not, and every pattern
-- LIKE can express is served: a prefix, a suffix, a single-character wildcard.
SELECT nickname FROM search_demo.users WHERE nickname LIKE '将军%' LIMIT 20;
SELECT nickname FROM search_demo.users WHERE nickname LIKE '将军%' LIMIT 20 ALLOW FILTERING;
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将_来%' LIMIT 20;

-- A query that is not paged needs a LIMIT, of at most 1000 (cqlsh pages by default; section 6c
-- ends with PAGING OFF, which these run under).
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%';
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 1001;

-- Paged, it needs none, on any index: two rows a page, in the index's order.
PAGING 2;
SELECT username FROM search_demo.users WHERE username LIKE '%ng%';
PAGING OFF;

-- It is one LIKE on the indexed column and nothing else. A restriction the index cannot apply is
-- refused rather than dropped: these queries do no post-filtering, so an accepted-and-ignored
-- predicate would return rows that do not match.
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' AND status = 0 LIMIT 20;
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' AND username LIKE '%user%' LIMIT 20;

-- A range on register_time belongs to the index ordered by it, so it needs the ORDER BY that
-- picks that index; and it is a range, not a point.
SELECT nickname FROM search_demo.users
  WHERE nickname LIKE '%将军%' AND register_time < '2024-03-01T00:00:00+0000' LIMIT 20;
SELECT nickname FROM search_demo.users
  WHERE nickname LIKE '%将军%' AND register_time = '2024-07-01T00:00:00+0000'
  ORDER BY register_time DESC LIMIT 20;

-- The username column has no index ordered by anything, so ORDER BY is refused on it.
SELECT username FROM search_demo.users WHERE username LIKE '%ng%' ORDER BY register_time DESC LIMIT 20;

-- Since every LIKE on the column goes to the index, a LIKE mixed with another restriction is
-- rejected rather than run as a filtered scan, ALLOW FILTERING or not. Dropping the indexes
-- restores filtered LIKE.
SELECT nickname FROM search_demo.users WHERE account_type = 0 AND nickname LIKE '%将军%' LIMIT 20 ALLOW FILTERING;
