# Substring search demo: `LIKE '%keyword%'` served by an index

A small, self-contained demo of substring search on ScyllaDB's `pattern_index`: the search box of
a live-streaming site, where a viewer types part of a display name and gets every account whose
nickname or username contains it.

```sql
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 20;
```

No `ALLOW FILTERING`, no table scan: the column carries a `pattern_index`, and the query is
answered by the Vector Store from an index of the short pieces of each value.

An index created with `order_by` answers the rest of the search box too: newest first, filtered
by date, a page at a time.

```sql
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%' AND register_time < '2024-03-01T00:00:00+0000'
  ORDER BY register_time DESC LIMIT 20;
```

Seventeen accounts, mostly CJK nicknames with a few Latin ones. Everything runs in two local
containers.

**How it works, one idea a page, with pictures and measurements: [design/](design/README.md).**

## What you need

- `podman` (rootless is fine), `buildah`, and `podman-compose` (`systemctl --user start podman.socket` first if compose complains).
- The `scylladb` submodule on its `pattern-index-poc-upstream-split` branch (default: `../scylladb`).
- The `vector-store` submodule on its `pattern-index-poc-upstream` branch (default: `../vector-store`).

The superproject's `pattern-index-poc-upstream` branch pins both. Released images do not have
ordering, paging or the options shown here, which is why both images are built locally.

## Set-up

```sh
./build-images.sh [scylla-src] [vector-store-src]   # builds localhost/scylla-substring:dev and
                                                    # localhost/vector-store-substring:dev
podman-compose up -d                                # scylla first, vector store when scylla is healthy
podman-compose exec scylla cqlsh -f /demo/schema.cql
podman-compose exec scylla cqlsh -f /demo/data.cql
./wait-for-indexes.sh                               # until the three indexes are SERVING
podman-compose exec scylla cqlsh                    # then paste queries from demo.cql
```

`podman-compose exec scylla cqlsh -f /demo/demo.cql` runs the whole script in one go, including the
deliberately failing statements of section 8, which cqlsh reports and moves past.
`podman exec substring-demo-scylla cqlsh ...` works just as well as `podman-compose exec scylla cqlsh ...`.

`./present.sh` opens cqlsh with the statements of `demo.cql` one key press away (PgDn types the next
one, pressed again runs it), for presenting the demo live; `./present.sh 0-7` leaves out the guard
rails of section 8, and `6` includes 6a to 6c. It needs `tmux` and `uv`; the keys and the rest are
described in [common/present.sh](../common/present.sh) and in the
[hybrid search demo](../hybrid-search-demo/README.md#presenting-it-live).

Tear down with `podman-compose down -v`.

## The schema

`search_demo.users` is the customer's table: an account id, a display name, a login name, and a
few attributes (see [schema.cql](schema.cql)).

An index answers in one order, fixed when it is created, and a query is served by the index whose
order fits it. So the nickname column has two indexes:

| column | index | options | serves |
|---|---|---|---|
| `nickname` | `users_nickname_sub` | `case_sensitive = 'false'` | `LIKE` with no `ORDER BY` |
| `nickname` | `users_nickname_newest` | `case_sensitive = 'false'`, `order_by = 'register_time DESC'` | `LIKE` with `ORDER BY register_time`, either way, and a range on it |
| `username` | `users_username_sub` | `case_sensitive = 'false'` | `LIKE` with no `ORDER BY` |

```sql
CREATE CUSTOM INDEX users_nickname_newest ON search_demo.users (nickname)
  USING 'pattern_index'
  WITH OPTIONS = {'case_sensitive': 'false', 'order_by': 'register_time DESC'};
```

The index options:

| option | default | meaning |
|---|---|---|
| `case_sensitive` | `true` | `true` matches like CQL `LIKE` does; `false` ignores letter case |
| `order_by` | none | up to four columns, each `ASC` or `DESC`, that the index keeps its rows ordered by; integer, `date`, `time` or `timestamp` columns |
| `partition_order` | `scattered` | the order of partitions where `order_by` does not decide: `scattered`, a fixed order unrelated to the token, or `token`, the order of a table scan ([why](design/08-where-rows-are-read.md)) |
| `min_gram`, `max_gram` | `1`, `3` | the shortest and longest indexed piece of a value, in characters ([why](design/01-pieces-of-a-value.md)) |
| `rarest_grams` | `4` | how many pieces of a long keyword are looked up |
| `segment_rows`, `rewrite` | `200000`, `true` | how the index node keeps its storage in shape ([why](design/04-narrow-pieces.md)) |

## The query

Rules worth knowing when writing your own:

- Every `LIKE` on a column with a pattern index goes to the index, with or without
  `ALLOW FILTERING`, and every pattern `LIKE` can express is served: `'%kw%'`, `'kw%'`, `'%kw'`,
  `_` for one character. The pattern may be a bind marker.
- The `LIKE` is the only restriction, except that a query on an index with `order_by` may add a
  range (`<`, `<=`, `>`, `>=`) on the first ordering column. Anything else is refused rather
  than dropped: these queries do no filtering afterwards, so a restriction that was accepted and
  ignored would return rows that do not match.
- `ORDER BY` must be a prefix of some index's `order_by` columns, all as declared or all
  reversed. A `LIKE` with no `ORDER BY` needs an index with no `order_by`.
- Every query is paged, as the drivers page any query, and a later page costs what the first
  did. A paged query needs no `LIMIT`. A query that is not paged needs a `LIMIT` of at most 1000.
- A page may hold fewer rows than asked for while more follow. Read until the driver reports no
  more pages.
- Without `ORDER BY` the rows come in the index's own order: fixed, so that paging is exact,
  but not the order of a table scan unless the index was created with
  `'partition_order': 'token'`.
- The index follows the table with a short delay, and rows are not checked against the table
  again.

## The demo, query by query

Outputs below are from a run on 2026-11-24; see [demo.cql](demo.cql) for the exact statements.

### 0. The data

```
 nickname     | username      | register_time                   | status
--------------+---------------+---------------------------------+--------
         司令 |      user0006 | 2024-01-07 00:00:00.000000+0000 |      0
       NG玩家 |       NGgamer | 2024-05-01 00:00:00.000000+0000 |      0
       宇将军 |      user0001 | 2024-01-01 00:00:00.000000+0000 |      0
       王将军 |      user0016 | 2024-07-01 00:00:00.000000+0000 |      0
       李将军 |      user0002 | 2024-02-01 00:00:00.000000+0000 |      0
         元帅 |      user0005 | 2024-01-06 00:00:00.000000+0000 |      0
     被禁将军 |      user0017 | 2024-07-02 00:00:00.000000+0000 |      1
         小明 |        925555 | 2024-06-01 00:00:00.000000+0000 |      0
     将军来了 | jiangjunlaile | 2024-03-01 00:00:00.000000+0000 |      0
         将领 |      user0004 | 2024-01-05 00:00:00.000000+0000 |      0
       GN小号 |            gn | 2024-01-09 00:00:00.000000+0000 |      0
       南宫月 |      user0007 | 2024-04-01 00:00:00.000000+0000 |      0
         宫南 |      user0009 | 2024-01-08 00:00:00.000000+0000 |      0
         小刚 |           925 | 2024-01-10 00:00:00.000000+0000 |      0
       国王NG |        kingNG | 2024-05-02 00:00:00.000000+0000 |      0
 小南宫粉丝团 |      user0008 | 2024-04-15 00:00:00.000000+0000 |      0
         小红 |       9255551 | 2024-06-02 00:00:00.000000+0000 |      0

(17 rows)
```

### 1. Containment

```sql
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 20;
```
```
 nickname | username
----------+---------------
   王将军 |      user0016
 将军来了 | jiangjunlaile
 被禁将军 |      user0017
   宇将军 |      user0001
   李将军 |      user0002

(5 rows)
```

将军 at the start, in the middle and at the end of the name, all found. Without the index this is
a `LIKE ... ALLOW FILTERING` that reads the whole table. A single character is a keyword too:
`LIKE '%将%'` adds 将领, six rows.

### 2. A substring, not a bag of characters

```sql
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%南宫%' LIMIT 20;
```
```
 nickname     | username
--------------+----------
       南宫月 | user0007
 小南宫粉丝团 | user0008

(2 rows)
```

宫南 has both characters in the other order and is not a match. `LIKE '%宫%'` finds all three.

### 3. Case-insensitive Latin

```sql
SELECT username, nickname FROM search_demo.users WHERE username LIKE '%ng%' LIMIT 20;
```
```
 username      | nickname
---------------+----------
 jiangjunlaile | 将军来了
       NGgamer |   NG玩家
        kingNG |   国王NG

(3 rows)
```

`'%NG%'` and `'%Ng%'` return the same three rows: with `case_sensitive = 'false'` both the values
and the keyword are lowercased. Note `jiangjunlaile`: containment is containment, and `ng` is in
the middle of it. The same works for the Latin part of a nickname: `nickname LIKE '%ng%'` finds
NG玩家 and 国王NG.

### 4. Digits

```sql
SELECT username, nickname FROM search_demo.users WHERE username LIKE '%925555%' LIMIT 20;
```
```
 username | nickname
----------+----------
  9255551 |     小红
   925555 |     小明

(2 rows)
```

925 is not a match for 925555, but `'%925%'` finds all three.

### 5. Keywords longer than `max_gram`

```sql
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军来了%' LIMIT 20;
```
```
 nickname | username
----------+---------------
 将军来了 | jiangjunlaile

(1 rows)
```

The index holds pieces of up to three characters. A four-character keyword is answered by
intersecting the rows that contain 将军来 and 军来了, then checking each candidate's stored value
for the whole keyword, so a name that happened to contain both pieces in different places would
still be excluded. `'%南宫粉丝团%'` and `'%jiangjun%'` work the same way; `'%将军来啦%'` returns
no rows. [Index the pieces of a value](design/01-pieces-of-a-value.md) has the picture.

### 6. LIMIT

```sql
SELECT nickname, register_time FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 2;
```
```
 nickname | register_time
----------+---------------------------------
   王将军 | 2024-07-01 00:00:00.000000+0000
 将军来了 | 2024-03-01 00:00:00.000000+0000

(2 rows)
```

The index stops after two matches. They are the first two of section 1: the index's own order,
which is fixed but means nothing to a user. A query that cares which two it gets says `ORDER BY`.

### 6a. ORDER BY

```sql
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%' ORDER BY register_time DESC LIMIT 20;
```
```
 nickname | register_time
----------+---------------------------------
 被禁将军 | 2024-07-02 00:00:00.000000+0000
   王将军 | 2024-07-01 00:00:00.000000+0000
 将军来了 | 2024-03-01 00:00:00.000000+0000
   李将军 | 2024-02-01 00:00:00.000000+0000
   宇将军 | 2024-01-01 00:00:00.000000+0000

(5 rows)
```

This query went to the other nickname index, `users_nickname_newest`. The order is the index's,
and it is global: the index walks its matches from the newest down, so a `LIMIT 2` of this query
is the first two rows here, not two arbitrary matches sorted afterwards.

```
... ORDER BY register_time ASC LIMIT 20;
  -> the same five, oldest first

... ORDER BY user_id DESC LIMIT 20;
  -> InvalidRequest: Pattern search queries can only be ordered by the index's columns
     (register_time DESC), in that order, not by user_id
```

The reverse is the same walk from the other end. Ordering by a column no index is ordered by is
refused rather than answered in the wrong order.
[Keep the index in the order the query asks for](design/02-the-index-in-query-order.md) explains
why this is what makes a page cheap.

### 6b. A range on the ordered column

The date filter of a search box. It goes to the index, which never looks at the excluded rows.

```sql
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%' AND register_time < '2024-03-01T00:00:00+0000'
  ORDER BY register_time DESC LIMIT 20;
```
```
 nickname | register_time
----------+---------------------------------
   李将军 | 2024-02-01 00:00:00.000000+0000
   宇将军 | 2024-01-01 00:00:00.000000+0000

(2 rows)
```

`<` excluded 将军来了, registered exactly on 2024-03-01. Both bounds work, and both are exact:

```sql
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%'
    AND register_time >= '2024-02-01T00:00:00+0000'
    AND register_time <= '2024-07-01T00:00:00+0000'
  ORDER BY register_time DESC LIMIT 20;
```
```
 nickname | register_time
----------+---------------------------------
   王将军 | 2024-07-01 00:00:00.000000+0000
 将军来了 | 2024-03-01 00:00:00.000000+0000
   李将军 | 2024-02-01 00:00:00.000000+0000

(3 rows)
```

### 6c. Paging

With `PAGING 2`, the five matches come back two at a time. cqlsh hides the page boundaries, and the
boundaries are the point, so [page-check.py](page-check.py) runs the same query through the driver
and prints each page as it arrives (`./page-check.py`, or `podman cp` it into the container and
run it there with the container's address if the host has no driver):

```
LIMIT 20, fetch_size 2:
  page 1: ['被禁将军', '王将军']  more=True
  page 2: ['将军来了', '李将军']  more=True
  page 3: ['宇将军']  more=False
  -> 3 pages, 5 rows, duplicates=False
LIMIT 3, fetch_size 2:
  page 1: ['被禁将军', '王将军']  more=True
  page 2: ['将军来了']  more=False
  -> 2 pages, 3 rows, duplicates=False
LIMIT 20, fetch_size 5000:
  page 1: ['被禁将军', '王将军', '将军来了', '李将军', '宇将军']  more=False
  -> 1 pages, 5 rows, duplicates=False

paged == unpaged: True
limit honoured: True
```

Each page carries the index's position forward, so the next page resumes the walk rather than
restarting it and skipping: page 50 costs what page 1 costs. The `LIMIT` bounds the query, not
the page: the second run stops after three rows across two pages.
[A cursor names a place in the order](design/03-a-cursor.md) has the picture.

### 7. Names change

```sql
UPDATE search_demo.users SET nickname = '大元帅' WHERE user_id = 2cfbb005-a436-44e4-aae1-7ba1d5c9427d;
DELETE FROM search_demo.users WHERE user_id = b2203663-516f-4118-a6fb-dc696a9cca73;   -- 司令
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username)
  VALUES (0fcde168-fffa-41b0-a08c-2664b9faec1e, 0, '新将军', '2024-08-01T00:00:00+0000', 0, 'newgeneral');
```

A moment later:

```
SELECT ... WHERE nickname LIKE '%大元帅%' LIMIT 20;      SELECT ... WHERE nickname LIKE '%司令%' LIMIT 20;
 nickname | username                                    nickname | username
----------+----------                                  ----------+----------
   大元帅 | user0005
(1 rows)                                               (0 rows)

SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 20;
 nickname | username
----------+---------------
   王将军 |      user0016
 将军来了 | jiangjunlaile
   新将军 |    newgeneral
 被禁将军 |      user0017
   宇将军 |      user0001
   李将军 |      user0002
(6 rows)

SELECT nickname, register_time ... WHERE nickname LIKE '%将军%' ORDER BY register_time DESC LIMIT 2;
 nickname | register_time
----------+---------------------------------
   新将军 | 2024-08-01 00:00:00.000000+0000
 被禁将军 | 2024-07-02 00:00:00.000000+0000
(2 rows)
```

The Vector Store follows the table through its change log (CDC), the same way it does for vector
and full-text indexes. In this run the new account was found 1.4 seconds after the insert, and it
is in both nickname indexes: among the matches of the plain query, and first in the newest-first
one. [demo.cql](demo.cql) then puts the three rows back so that the demo can be run again. When
the file is run in one go the `SELECT`s come a moment too early and show the old state; repeat them.

### 8. Guard rails

```
SELECT nickname FROM search_demo.users WHERE nickname LIKE '将军%' LIMIT 20;
  -> 将军来了                       (a prefix)

SELECT nickname FROM search_demo.users WHERE nickname LIKE '将军%' LIMIT 20 ALLOW FILTERING;
  -> 将军来了                       (still the index: ALLOW FILTERING does not change where a LIKE goes)

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将_来%' LIMIT 20;
  -> 将军来了                       (a single-character wildcard)

PAGING OFF
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%';
  -> InvalidRequest: Pattern search queries require a LIMIT unless they are paged

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 1001;
  -> InvalidRequest: Pattern search queries require a LIMIT that is not greater than 1000 unless
     they are paged. LIMIT was 1001

PAGING 2
SELECT username FROM search_demo.users WHERE username LIKE '%ng%';
  -> jiangjunlaile, NGgamer, kingNG  (paged, no LIMIT, on an index without order_by)

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' AND status = 0 LIMIT 20;
  -> InvalidRequest: Pattern search queries cannot restrict status: only the indexed column
     nickname may be restricted

SELECT nickname FROM search_demo.users
  WHERE nickname LIKE '%将军%' AND register_time < '2024-03-01T00:00:00+0000' LIMIT 20;
  -> InvalidRequest: Pattern search queries cannot restrict register_time: only the indexed
     column nickname may be restricted
     (with no ORDER BY the query goes to the index that has no register_time)

SELECT nickname FROM search_demo.users
  WHERE nickname LIKE '%将军%' AND register_time = '2024-07-01T00:00:00+0000'
  ORDER BY register_time DESC LIMIT 20;
  -> InvalidRequest: Pattern search queries support only range restrictions (<, <=, >, >=) on the
     ordered column register_time

SELECT username FROM search_demo.users WHERE username LIKE '%ng%' ORDER BY register_time DESC LIMIT 20;
  -> InvalidRequest: Pattern search queries on an index without order_by return rows in table
     order, as a filtered LIKE does, and cannot be ordered: order by columns an index declares in
     its 'order_by' option

SELECT nickname FROM search_demo.users
  WHERE account_type = 0 AND nickname LIKE '%将军%' LIMIT 20 ALLOW FILTERING;
  -> InvalidRequest: Pattern search queries cannot restrict account_type: only the indexed column
     nickname may be restricted
```

Every `LIKE` on a column with a pattern index goes to the index, `ALLOW FILTERING` or not, and
there is no fallback to a scan. The query is strict about its shape, so that what it promises, an
index lookup, is what it does. Dropping the indexes restores filtered `LIKE`.

One of these messages is out of date: an index without `order_by` no longer returns "table order,
as a filtered LIKE does" by default. The same sentence is in the warning `CREATE INDEX` prints.

## Under the hood

The Vector Store's HTTP API shows what CQL is talking to:

```sh
curl -s http://127.0.0.1:6080/api/v1/indexes
```
```json
[{"keyspace":"search_demo","index":"users_username_sub",
  "options":{"type":"pattern","min_gram":1,"max_gram":3,"case_sensitive":false},
  "status":"SERVING","count":17,"build_progress":100.0},
 {"keyspace":"search_demo","index":"users_nickname_newest",
  "options":{"type":"pattern","order_by":"register_time DESC","min_gram":1,"max_gram":3,"case_sensitive":false},
  "status":"SERVING","count":17,"build_progress":100.0},
 {"keyspace":"search_demo","index":"users_nickname_sub",
  "options":{"type":"pattern","min_gram":1,"max_gram":3,"case_sensitive":false},
  "status":"SERVING","count":17,"build_progress":100.0}]
```

The request ScyllaDB sends for the newest-first query, and its answer: primary keys only.
ScyllaDB then reads those rows from the table, as it does after a vector or a full-text search.

```sh
curl -s -X POST http://127.0.0.1:6080/api/v1/indexes/search_demo/users_nickname_newest/like \
     -H 'content-type: application/json' -d '{"pattern":"%将军%","limit":10}'
```
```json
{"primary_keys":{"user_id":["2a8083ad-308e-42ac-9681-b0f21282e7da","7bd0df74-f528-47b7-921e-fb8a45a30208",
  "2f10c77a-e76a-49f7-8f5c-4646923476e6","e236ee35-83ee-4a12-b3cf-5205bda686c1","ac195af8-6535-476f-b876-fb1cc9a96946"]}}
```

The keys come back in the index's order, newest first. There is no `next_cursor`: ten were asked
for and five found, so there is nothing to resume from. Ask for two and there is:

```sh
curl -s -X POST http://127.0.0.1:6080/api/v1/indexes/search_demo/users_nickname_newest/like \
     -H 'content-type: application/json' -d '{"pattern":"%将军%","limit":2}'
```
```json
{"primary_keys":{"user_id":["2a8083ad-308e-42ac-9681-b0f21282e7da","7bd0df74-f528-47b7-921e-fb8a45a30208"]},
 "next_cursor":"{\"prefix\":[9223370317062775807,102148191987806497,0,0,0],\"primary_key\":{\"user_id\":\"7bd0df74-f528-47b7-921e-fb8a45a30208\"}}"}
```

One cursor per page. It names the last row of the page by its place in the index's order (the
ordering column, then the partition's place) and its primary key, so that the next page resumes
after exactly that row. ScyllaDB puts it in the driver's paging state and sends it back as
`cursor` with the next request, without reading it.

## How it works, and how fast it is

The ideas behind the index, one a page, each with an example, a picture and what was measured:
**[design/](design/README.md)**.

On one ScyllaDB node and one index node with 4 vCPUs each, 10 million names and a page of 20:

| Query | Throughput |
|---|---|
| A frequent two-character keyword, any order | 16,800 to 17,500 queries/s |
| The same with 5,000 writes/s to the table | 12,300 to 13,600 queries/s |
| An eight-character keyword | 11,300 to 11,500 queries/s |
| A keyword that matches nothing | 47,000 to 54,000 queries/s |

The measurements of the earlier stages of this proof of concept, as they were written at the
time, are in [results-history.md](results-history.md).

## Known limits

- The index lives in the index node's memory, about 0.3 GB per million names, and each order is
  an index of its own.
- The `LIKE` is the only restriction, apart from a range on the first ordering column.
- Results are eventually consistent: a row written a moment ago may not be found yet.
- For frequent keywords, ScyllaDB reading the rows of a page is now the slowest step.
- What is settled and what we expect to change is marked idea by idea in
  [design/](design/README.md).
