# Substring search demo: `LIKE '%keyword%'` served by an index

A small, self-contained demo of ScyllaDB's `substring-index` branch together with the Vector
Store's `substring-index` branch: the search box of a live-streaming site, where a viewer types
part of a display name and gets every account whose nickname or username contains it.

```sql
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 20;
```

No `ALLOW FILTERING`, no table scan: the column carries a `substring_index`, and the query is
answered by the Vector Store from an n-gram index of the column.

An index created with an `order_by` column answers the rest of the search box too -- newest first,
filtered by date, a page at a time:

```sql
SELECT nickname, register_time FROM search_demo.users
  WHERE nickname LIKE '%将军%' AND register_time < '2024-03-01T00:00:00+0000'
  ORDER BY register_time DESC LIMIT 20;
```

Seventeen accounts, mostly CJK nicknames with a few Latin ones. Everything runs in two local
containers.

## What you need

- `podman` (rootless is fine), `buildah`, and `podman-compose` (`systemctl --user start podman.socket` first if compose complains).
- The `scylladb` submodule, on its `substring-index` branch (default: `../scylladb`).
- The `vector-store` submodule, on its `substring-index` branch (default: `../vector-store`).
  No released image has the substring index yet, which is why both images are built locally.

## Set-up

```sh
./build-images.sh [scylla-src] [vector-store-src]   # builds localhost/scylla-substring:dev and
                                                    # localhost/vector-store-substring:dev
podman-compose up -d                                # scylla first, vector store when scylla is healthy
podman-compose exec scylla cqlsh -f /demo/schema.cql
podman-compose exec scylla cqlsh -f /demo/data.cql
./wait-for-indexes.sh                               # the Vector Store full-scans the table once per index
podman-compose exec scylla cqlsh                    # then paste queries from demo.cql
```

`podman-compose exec scylla cqlsh -f /demo/demo.cql` runs the whole script in one go, including the
deliberately failing statements of section 8, which cqlsh reports and moves past.
`podman exec substring-demo-scylla cqlsh ...` works just as well as `podman-compose exec scylla cqlsh ...`.

Tear down with `podman-compose down -v`.

## The schema

`search_demo.users` is the customer's table: an account id, a display name, a login name, and a
few attributes. Each text column gets one index (see [schema.cql](schema.cql)):

| column | type | index | options |
|---|---|---|---|
| `nickname` | text | `users_nickname_sub`, `substring_index` | `case_sensitive = 'false'`, `order_by = 'register_time'` |
| `username` | text | `users_username_sub`, `substring_index` | `case_sensitive = 'false'` |

```sql
CREATE CUSTOM INDEX users_nickname_sub ON search_demo.users (nickname)
  USING 'substring_index'
  WITH OPTIONS = {'case_sensitive': 'false', 'order_by': 'register_time'};
```

The two indexes differ deliberately: only the nickname one is ordered, so the demo can show what an
index without `order_by` will not do.

The index options:

| option | default | meaning |
|---|---|---|
| `min_gram` | `1` | the shortest indexed substring, in characters; a shorter keyword is not served |
| `max_gram` | `3` | the longest indexed substring; a longer keyword is answered from its pieces and verified |
| `case_sensitive` | `true` | `true` matches like CQL `LIKE` does; `false` lowercases both the column and the keyword |
| `order_by` | none | a column the index keeps its matches sorted by, newest first; enables `ORDER BY`, a range on that column, and paging |

`order_by` must name an integer or time column of the table (`tinyint`, `smallint`, `int`, `bigint`,
`counter`, `timestamp`, `time`, `date`). The index carries that column's value alongside each
indexed name and walks its matches from the highest value down, so the order is global rather than a
re-sort of one page, and a page can resume where the last one stopped.

Both are `1..8`, `min_gram <= max_gram`. The Vector Store stores every substring of
`min_gram..max_gram` characters of each value as a term of a Tantivy index, with the row's key. A
keyword of at most `max_gram` characters is one term lookup; a longer one is the intersection of
its `max_gram`-character pieces, each candidate then checked against the stored value, so the
answer is exact either way.

## The query

Rules worth knowing when writing your own:

- The pattern is a literal keyword between two `%`: `LIKE '%keyword%'`. A `%`, `_` or `\` inside
  the keyword, a missing `%` on either side, or a keyword shorter than `min_gram` characters is not
  served by the index, and the query behaves exactly as it did before the index existed: it needs
  `ALLOW FILTERING` and scans.
- The keyword may be a bind marker, `LIKE ?`. The pattern is then checked when the statement is
  executed; a pattern the index does not serve is rejected at that point rather than scanned.
- `LIMIT` is mandatory and at most 1000. It bounds the whole query, not one page.
- On an index with `order_by`, the query may add `ORDER BY <that column> DESC` and a range on that
  column (`<`, `<=`, `>`, `>=`). Only that column, and only `DESC`. Without `order_by` neither is
  accepted, and the result order is whatever order the index returns the keys in.
- Nothing else in the `WHERE`, no `GROUP BY`, no aggregates. A restriction the index cannot apply is
  rejected rather than dropped: these queries do no post-filtering, so accepting one and ignoring it
  would return rows that do not match.
- Paging works on an index with `order_by`: each page tells the index where the last one stopped, so
  page 50 costs what page 1 costs. Without `order_by` there is no position to resume from, and the
  whole result comes in one page with a warning, as for the other external searches.
- Latin case: CQL `LIKE` is case-sensitive and so is the index by default. The demo indexes are
  created with `case_sensitive = 'false'`, since that is what a search box wants.

## The demo, query by query

Outputs below are from a real run; see [demo.cql](demo.cql) for the exact statements.

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
 被禁将军 |      user0017
   李将军 |      user0002
   宇将军 |      user0001
 将军来了 | jiangjunlaile
   王将军 |      user0016

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
 小南宫粉丝团 | user0008
       南宫月 | user0007

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
        kingNG |   国王NG
       NGgamer |   NG玩家

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
   925555 |     小明
  9255551 |     小红

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

The index holds substrings of up to three characters. A four-character keyword is answered by
intersecting the rows that contain 将军来 and 军来了, then checking each candidate's stored value
for the whole keyword, so a name that happened to contain both pieces in different places would
still be excluded. `'%南宫粉丝团%'` and `'%jiangjun%'` work the same way; `'%将军来啦%'` returns
no rows.

### 6. LIMIT

```sql
SELECT nickname, register_time FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 2;
```
```
 nickname | register_time
----------+---------------------------------
 被禁将军 | 2024-07-02 00:00:00.000000+0000
   王将军 | 2024-07-01 00:00:00.000000+0000

(2 rows)
```

The index stops after two matches. With `order_by` set, the two it stops at are the two newest --
the stop is at the right end of the order, not wherever the walk happened to be.

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

The order is the index's, not the base table's, and it is global: the index walks its matches from
the newest down, so a `LIMIT 2` of this query is the first two rows here rather than two arbitrary
matches re-sorted.

```
... ORDER BY register_time ASC LIMIT 20;
  -> InvalidRequest: Substring search queries can only be ordered DESC

... ORDER BY user_id DESC LIMIT 20;
  -> InvalidRequest: Substring search queries can only be ordered by register_time, the column the
     index was created with, not user_id
```

The index walks one column in one direction. Ordering by anything else, or the other way, is refused
rather than answered in the wrong order.

### 6b. A range on the ordered column

The date filter of a search box. It is pushed down to the index, which never looks at the excluded
rows, rather than applied to the rows afterwards.

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
and prints each page as it arrives (`./page-check.py`, or `podman cp` it into the container if the
host has no driver):

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

paged == unpaged: True
```

Each page carries the index node's position forward, so the next page resumes the walk rather than
restarting it and skipping -- the cost of page 50 is the cost of page 1, which is the whole point of
a cursor over an offset. The `LIMIT` bounds the query, not the page: the second run stops after
three rows across two pages.

### 7. Names change

```sql
UPDATE search_demo.users SET nickname = '大元帅' WHERE user_id = 2cfbb005-a436-44e4-aae1-7ba1d5c9427d;
DELETE FROM search_demo.users WHERE user_id = b2203663-516f-4118-a6fb-dc696a9cca73;   -- 司令
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username)
  VALUES (0fcde168-fffa-41b0-a08c-2664b9faec1e, 0, '新将军', '2024-08-01T00:00:00+0000', 0, 'newgeneral');
```

A few seconds later:

```
SELECT ... WHERE nickname LIKE '%大元帅%' LIMIT 20;      SELECT ... WHERE nickname LIKE '%司令%' LIMIT 20;
 nickname | username                                    nickname | username
----------+----------                                  ----------+----------
   大元帅 | user0005
(1 rows)                                               (0 rows)

SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 20;
 nickname | username
----------+---------------
 将军来了 | jiangjunlaile
 被禁将军 |      user0017
   王将军 |      user0016
   李将军 |      user0002
   宇将军 |      user0001
   新将军 |    newgeneral
(6 rows)
```

The Vector Store follows the table through CDC, the same way it does for vector and full-text
indexes; in this run every change was visible within four seconds. [demo.cql](demo.cql) then puts
the three rows back so that the demo can be run again. When the file is run in one go the three
`SELECT`s come a moment too early and show the old state; repeat them.

### 8. Guard rails

```
SELECT nickname FROM search_demo.users WHERE nickname LIKE '将军%' LIMIT 20;
  -> InvalidRequest: Cannot execute this query as it might involve data filtering ... use ALLOW FILTERING

SELECT nickname FROM search_demo.users WHERE nickname LIKE '将军%' LIMIT 20 ALLOW FILTERING;
  -> 将军来了                       (a filtered scan, as on a table without the index)

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将_来%' LIMIT 20;
  -> InvalidRequest: Cannot execute this query as it might involve data filtering ...

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%';
  -> InvalidRequest: Substring search queries require a LIMIT

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 1001;
  -> InvalidRequest: Substring search queries require a LIMIT that is not greater than 1000. LIMIT was 1001

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' AND status = 0 LIMIT 20;
  -> InvalidRequest: Substring search queries cannot restrict status: only the indexed column
     nickname and the ordered column register_time may be restricted

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%'
  AND register_time = '2024-07-01T00:00:00+0000' LIMIT 20;
  -> InvalidRequest: Substring search queries support only range restrictions (<, <=, >, >=) on the
     ordered column register_time

SELECT username FROM search_demo.users WHERE username LIKE '%ng%' ORDER BY register_time DESC LIMIT 20;
  -> InvalidRequest: ORDER BY requires the substring index to have been created with an 'order_by' option
```

A prefix pattern, or any pattern with a wildcard inside the keyword, is not containment: the index
steps aside and `LIKE` behaves exactly as before, `ALLOW FILTERING` and a scan. The containment
query itself is strict about its shape, so that what it promises, an index lookup, is what it does.

The strictness is not fussiness. These queries do no post-filtering: whatever the coordinator does
not send to the index node is not applied anywhere. A restriction that was accepted and then ignored
would return rows that do not match the query, which is worse than a rejection, so anything the
index node cannot apply exactly is refused.

The username index is created without `order_by`, and shows the other side of it: no `ORDER BY`, no
range, and paging it returns the whole result in one page with

```
Warnings :
Paging is not supported for Substring Search queries. The entire result set has been returned.
```

One limit of this stage shows in the last statement of the section: the index is chosen as soon as
the `LIKE` fits it, `ALLOW FILTERING` or not, so `account_type = 0 AND nickname LIKE '%将军%' ...
ALLOW FILTERING` is rejected rather than run as a filtered scan. Falling back to the scan in that
case is the natural next step.

## Under the hood

The Vector Store's HTTP API shows what CQL is talking to:

```sh
curl -s http://127.0.0.1:6080/api/v1/indexes
```
```json
[{"keyspace":"search_demo","index":"users_nickname_sub",
  "options":{"type":"substring","order_by":"register_time","min_gram":1,"max_gram":3,"case_sensitive":false},
  "status":"SERVING","count":17,"build_progress":100.0},
 {"keyspace":"search_demo","index":"users_username_sub",
  "options":{"type":"substring","min_gram":1,"max_gram":3,"case_sensitive":false},
  "status":"SERVING","count":17,"build_progress":100.0}]
```

The request Scylla sends for `nickname LIKE '%将军%' LIMIT 10`, and its answer: primary keys only,
no scores. Scylla then reads those rows from the base table, as it does after an `ANN()` or a
`BM25()` search.

```sh
curl -s -X POST http://127.0.0.1:6080/api/v1/indexes/search_demo/users_nickname_sub/contains \
     -H 'content-type: application/json' -d '{"query":"将军","limit":10}'
```
```json
{"primary_keys":{"user_id":["2a8083ad-308e-42ac-9681-b0f21282e7da","7bd0df74-f528-47b7-921e-fb8a45a30208",
  "2f10c77a-e76a-49f7-8f5c-4646923476e6","e236ee35-83ee-4a12-b3cf-5205bda686c1","ac195af8-6535-476f-b876-fb1cc9a96946"]}}
```

The keys come back in the order the index walked them -- newest first, because this index has
`order_by` -- and both paths of Scylla's base-table read preserve that order, which is why no sort
value needs to cross the wire per row. There is no `next_cursor` here: ten were asked for and five
found, so the walk ran out and there is nothing to resume from.

Ask for two and there is:

```sh
curl -s -X POST http://127.0.0.1:6080/api/v1/indexes/search_demo/users_nickname_sub/contains \
     -H 'content-type: application/json' -d '{"query":"将军","limit":2}'
```
```json
{"primary_keys":{"user_id":["2a8083ad-308e-42ac-9681-b0f21282e7da","7bd0df74-f528-47b7-921e-fb8a45a30208"]},
 "next_cursor":"{\"sort_key\":9223373756646775808,\"primary_key\":{\"user_id\":\"7bd0df74-f528-47b7-921e-fb8a45a30208\"}}"}
```

One cursor per page, not per row. It is an opaque string naming the last row of the page: its
sort key and its primary key, so that the next page resumes after exactly that row even among
rows sharing a sort value. Scylla puts it in the paging state and sends it back as `cursor` on
the next request without reading it.

The sort key inside is the node's own encoding (`2^63 + 1719792000000`: the timestamp of 王将军,
`2024-07-01T00:00:00Z`, in milliseconds, with the sign bit flipped so that negative timestamps
sort below positive ones in unsigned comparison) and nothing outside the node needs to know it.
A range on the ordered column travels as the column's own values: `registered_at >= X AND
registered_at < Y` becomes
`"min_sort_value":{"value":"2024-01-01T00:00:00.000Z","inclusive":true}` and
`"max_sort_value":{"value":"2024-07-01T00:00:00.000Z","inclusive":false}`, and the node encodes
them the same way it encodes the column at ingestion.

The routing on the Scylla side is the ordinary secondary-index path: a `LIKE` is a column
restriction, and a `substring_index` reports that it supports one when the pattern is
`%literal%` (checked at prepare for a literal, at execute for a bind marker). A query the analysis
hands to such an index is then prepared as a substring search statement instead of the usual
view read. `docs/dev/substring_search.md` in the Scylla checkout describes the design.

## Performance at 10M rows

The demo above runs on 17 rows, which says the feature works but nothing about whether it is
usable. This section is one run of `substring_test.SubstringSearchTest` from
[scylla-cluster-tests](../scylla-cluster-tests) against a real cluster on AWS, at the design
target of 10M names. It is a feasibility check, not a benchmark: one run, one cluster shape, no
repeats.

### What was measured

| | |
|---|---|
| Rows | 10,000,000 synthetic names, CJK-heavy, 2–10 characters |
| ScyllaDB | 1 × `i4i.xlarge`, substring branch, tablets |
| Vector Store | 1 × `c8g.xlarge` (4 ARM cores), `substring-index` branch built from source |
| Loader | 1 × `c5.2xlarge` running `latte` |
| Index options | `min_gram=1`, `max_gram=3`, `case_sensitive=false` |
| Query | `SELECT user_id FROM ... WHERE name LIKE '%kw%' LIMIT 20` |
| Run | `20260922-115919-278074`, 2026-09-22, eu-west-1 |

The index was created *before* the rows were written, so the Vector Store ingested through CDC
while `latte` was still loading, rather than building afterwards over a full scan.

### Ingestion and index size

| | |
|---|---|
| Load | 10M names in ~30 min wall clock |
| Index caught up | **12 s** after the last row landed (10,000,000 of 10,000,000) |
| Index settled | 32 segments, ~30 s later |
| Index size | **328,619,593 bytes ≈ 313 MiB** |
| Per name | **32.86 bytes** |

The index keeping pace with the load to within 12 seconds is the result that matters here: at this
rate, incremental indexing is not a phase you wait for, and the "when is the index ready" question
that shaped the test design turns out to be nearly moot at this scale.

Two notes on the numbers. The 30-minute load is not a load-rate measurement — `latte` ran once per
100k-name shard and the per-shard wall time was 18.3 s, of which only ~1.8 s was loading (~54k
names/s); the rest was container startup. And 313 MiB is far below the "a few GB" this branch's
docs estimated, though the corpus is synthetic with low character diversity, so a real corpus with
a wider character set will produce more distinct grams and a larger index.

### The query sets

Keywords are drawn from the corpus itself, so every one of them matches something. The three sets
the AWS plan uses differ in how much work they make the index do:

| set | keyword | why it is in the plan |
|---|---|---|
| `char1` | 1 character | The hot case. A single character is carried by a large share of the names, so the candidate set is huge and stopping at `LIMIT` is what keeps it cheap. |
| `char2` | 2 characters | The typical search-box query, and the shape to judge the design by. Both `char1` and `char2` are within `max_gram = 3`, so each is a single term lookup. |
| `char4` | 4 characters | Longer than `max_gram`, so the index intersects 3-grams and then verifies every candidate against the stored text. The most expensive shape it serves. |

Two further sets, `latin` (case folding on both sides) and `miss` (keywords no name contains),
exist in the generator and run in the local docker plan, but are left out of the AWS plan: folding
is cheap and an empty answer is the floor rather than the question.

### Query latency and throughput

Five phases, 120 s each, `LIMIT 20`, zero errors, every query returning its full 20 rows.

Two latencies matter here and they are not the same thing. **Service time** is how long a request
actually took once it was sent. **Client-observed latency** additionally counts the time a request
waited to be sent, so when the requested rate is above what the cluster can serve it measures a
growing backlog rather than the system. Three of these five phases asked for 10,000 QPS and got
less, so for those only the service time means anything.

| set | rate | conc. | throughput | service time | client p99 |
|---|---|---|---|---|---|
| char2 | 2,000 | 16 | 2,000 op/s | **0.67 ms** | 1.49 ms |
| char2 | unthrottled | 128 | 9,610 op/s | **13.29 ms** | 20.68 ms |
| char2 | 10,000 | 64 | 9,704 op/s | **6.57 ms** | *saturated* |
| char1 | 10,000 | 64 | 9,309 op/s | **6.85 ms** | *saturated* |
| char4 | 10,000 | 64 | 9,512 op/s | **6.70 ms** | *saturated* |

Service time is latte's mean request latency; only the first two rows have a client-observed
latency worth printing, since the other three are queueing (their mean client latency was 1.8 s,
4.5 s and 2.9 s respectively — a measure of the backlog, not of the cluster).

At a realistic 2,000 QPS a containment query is served in **0.67 ms**, p99 **1.49 ms**, against a
100 ms budget. At the ceiling of ~9.6k QPS service time is **6.6–13.3 ms** depending on how many
requests are in flight, and the closed-loop p99 is **20.7 ms** — still five times inside budget.

The service-time column is also where the shape of the answer shows up: at the same offered rate
and concurrency, `char1`, `char2` and `char4` are served in 6.85, 6.57 and 6.70 ms. Four-character
keywords cost a gram intersection plus verification of every candidate and one-character keywords
sweep a large fraction of the corpus, yet all three land within 4% of each other.

### Where the ceiling is

The ceiling is real rather than a client-side artifact, and it is **ScyllaDB's base-table read
path, not the index**.

The client was not the limit. `latte` used 2.8% CPU on the loader in every saturated phase — 27 s
of CPU over 120 s, about 0.23 of 8 cores — while its concurrency slots sat 97–98% occupied. Nor
was the concurrency setting badly chosen: raising it from 64 to 128 in-flight requests moved
throughput from 9,704 to 9,610 op/s, i.e. not at all, while service time went from 6.57 ms to
13.29 ms — exactly doubled. Throughput fixed and service time rising in step with concurrency is
saturation by definition; past that point extra concurrency buys latency and nothing else.
Little's Law holds in both rows (9,704 × 6.57 ms = 63.7 in flight against 62 reported;
9,610 × 13.29 ms = 127.7 against 126), which is what says these are real service times rather
than an artifact of how the client scheduled its requests.

The Scylla node was the busy one. During the unthrottled phase its monitoring showed **86% load
across its 4 cores**, plateaued, with read p99 at 7 ms and no write traffic. Its read latency
degraded from 0.96 ms at 2,000 QPS to 10.52 ms at the ceiling — most of the 13.5 ms a query took.

This also explains the uniformity in the service times: 6.57, 6.85 and 6.70 ms for three query
shapes that cost the index very different amounts. Every query is `LIMIT 20`, so whatever the
index does, Scylla then fetches exactly 20 rows — identical work every time. At 9,610 op/s that is
192,205 rows/s off one `i4i.xlarge`. The constant per-query cost dominates the variable index-side
cost, which is why query shape barely moves the number, and it is why the index's own contribution
cannot be separated out from this run.

So the design target of 10k QPS at p99 < 100 ms was met on latency by a wide margin and missed on
throughput by 4%, on a cluster whose limiting component is a single 4-core database node doing
ordinary primary-key reads. Scaling out the ScyllaDB side is the lever; the index was not what ran
out first. One thing this run does not show is the Vector Store node's own CPU, so while the
evidence points firmly at Scylla, a second constraint on the index node cannot be fully excluded.

### Reproducing

```sh
cd scylla-cluster-tests
python3 data_dir/latte/substring_search/generate_local_dataset.py \
    --dataset names_10M --names 10000000 --shards 100 --qrels-cap 0
export SCT_ENABLE_ARGUS=false
export SCT_UNIFIED_PACKAGE=<url of the scylla unified tarball built from the substring branch>
./docker/env/hydra.sh run-test substring_test.SubstringSearchTest.test_substring_search \
    --backend aws --config test-cases/substring-search/substring-search-test.yaml
```

`docs/substring-search-test.md` in the SCT checkout covers the test in full, including the docker
variant that runs the same flow locally and additionally checks recall and precision against ground
truth — correctness is verified there rather than in the AWS run, which measures only speed.

## Performance at 10M rows, stage 2: the first ordered runs (2026-09-25)

This section is what the stage-2 branches measured on 2026-09-25, the evening the segment cap
was written: the runs that found the fixed per-query cost, rejected the FAST primary id, and
showed the cap at work. The one-run comparison of the next section repeats the cap variants
against the default with the two-pass verification in and adds stage 3. It was measured on the
same cluster shape as the stage-1 run (1 × `i4i.xlarge` ScyllaDB, 1 × `c8g.xlarge` Vector Store
with 4 cores, 1 × `c5.2xlarge` loader), with the ordered query of section 6a and the paging of
section 6c. Several runs in one evening, one cluster shape, no repeats: a feasibility check.

### The design in one paragraph

The index keeps the names in chunks, called segments, and each segment knows the oldest and
newest `register_time` it holds. An ordered query visits segments newest-first and skips every
segment that cannot hold anything newer than the page already has, so a deep page costs what
the first page costs. That only works if each segment covers a narrow slice of time, which is
not what an index does on its own: it merges chunks by size, regardless of what they hold.
`poc_option_2`, a row cap per segment, makes the index merge only neighbours in time and never
past the cap, so rows that arrive in time order stay in slices of time. Long keywords get a
separate improvement: a keyword longer than `max_gram` yields candidates that each need their
stored name read to confirm the match, and the index sorts the candidates by time first and
confirms from the newest down, stopping as soon as the page cannot change. Design and
reasoning:
[`vector-store/docs/dev/substring/stage-2-ordering.md`](../vector-store/docs/dev/substring/stage-2-ordering.md).

### What was measured

Three indexes created before the load and fed by the same CDC stream: Tantivy's default merging,
the cap at 250,000 rows, the cap at 100,000 rows. Every index was asked the same questions for
120 s each, 20 rows per page, 10,000 queries per second offered with 64 in flight. The walk is
the Vector Store's own count of microseconds in the index per query; the throughput is what
`latte` achieved.

| | default | cap 250k | cap 100k |
|---|---|---|---|
| segments, mean span, widest | 16, 10.8%, 35.7% | 41, 3.3%, 5.2% | 100, 1.0%, 1.0% |
| caught up after the load | 15 s | 15 s | 15 s |
| 2-char keyword, page 1 | 10.2k/s, 28 µs | 9.6k/s, 111 µs | 9.8k/s, 81 µs |
| 2-char keyword, unthrottled | — | 9.7k/s | 10.1k/s |
| 2-char keyword, deep page (cursor at the median) | 3.1k–4.5k/s on earlier layouts | 9.75k/s, 168 µs | **9.85k/s, 76 µs** |
| 1-char keyword | — | 10.0k/s | 10.0k/s |
| 4-char keyword (verified) | — | 9.6k/s, 112 stored names read | 5.8k/s, 207 read |

What it settled:

- **The cap is what makes deep pages cheap.** On the default layout a deep page landed in a
  1.3M-row segment and scanned 76,000 postings; with the 100k cap it scans 3,000 and costs what
  page 1 costs, the design's claim. Neither cap slowed ingestion.
- **Page 1 had a fixed cost of about 450 µs** before this run's fixes: every query opened every
  segment's sort column to read its bounds. Caching the columns per segment removed it; the
  numbers above are with the cache.
- **A `FAST` primary-id column is not worth its bytes** (`poc_option_1`, measured 3.9k/s against
  7.1k/s on the same load): resolving the page from the store costs 20 µs.
- **The verified path was the one shape below target**: 207 stored names read for a 4-character
  keyword at the 100k cap, because a single narrow newest segment scanned in ascending time
  order makes every later candidate beat the page. The two-pass verification (confirm from the
  newest down, stop when the page cannot change) is on this branch; its measurement at 10M is in
  the stage-3 report (40 reads, 10.0k/s).

### Reproducing

```sh
cd scylla-cluster-tests
export SCT_ENABLE_ARGUS=false
export SCT_UNIFIED_PACKAGE=<presigned url of the scylla unified tarball built from the stage-2 branch>
export SCT_SEARCH_TEST_CONFIG=data_dir/latte/substring_search/aws_page1_config.yaml
./docker/env/hydra.sh run-test substring_test.SubstringSearchTest.test_substring_search \
    --backend aws --config test-cases/substring-search/substring-search-test.yaml
```

## Performance at 10M rows, stages 2 and 3: ordering, paging and segment balancing

The stage-1 run above measures containment alone: any twenty matching rows, in any order. The
search box wants the *newest* twenty and a next page, which is what stage 2 adds (`ORDER BY`,
the range, the cursor, the segment cap, two-pass verification); stage 3 adds the background
rewrite that repairs an index created on an already loaded table. Serving an order means the
index can no longer stop at the first twenty matches; it has to know which twenty are the
newest. This section is one run of the same SCT test on the stage-3 branches, 2026-09-27,
with the ordered query of section 6a and the paging of section 6c, on the same cluster shape as
before (1 × `i4i.xlarge` ScyllaDB, 1 × `c8g.xlarge` Vector Store with 4 cores, 1 × `c5.2xlarge`
loader; run `20260926-220437-885482`, eu-west-1). It is one run, not a benchmark.

### The design in one paragraph

The index keeps the names in chunks, called segments, and each segment knows the oldest and
newest `register_time` it holds. An ordered query visits segments newest-first and skips every
segment that cannot hold anything newer than the page already has, so a deep page costs what
the first page costs. That only works if each segment covers a narrow slice of time, which is
not what an index does on its own: it merges chunks by size, regardless of what they hold. Two
options on the index fix that. `poc_option_2` (a row cap per segment) makes the index merge only
neighbours in time and never past the cap, so rows that arrive in time order stay in slices of
time. `poc_option_3` (the rewrite) repairs an index created *after* the table was loaded, where
every chunk spans all of time: in the background it moves the rows, one slice of time at a
time, into narrow chunks. Long keywords get a separate improvement: a keyword longer than
`max_gram` yields candidates that each need their stored name read to confirm the match, and
the index now sorts the candidates by time first and confirms from the newest down, stopping as
soon as the page cannot change. Design and reasoning:
[`vector-store/docs/dev/substring/stage-2-ordering.md`](../vector-store/docs/dev/substring/stage-2-ordering.md).

### What was compared

Six indexes on the same corpus, so that each question is answered by one difference. Four were
created before the load and ingested through CDC while `latte` wrote; two were created on the
loaded table and built by the Vector Store's full scan, which reads the table in storage order,
not time order.

| index | created | options | the question it answers |
|---|---|---|---|
| `default` | before the load | none | the baseline: the index's own merging |
| `p3a_100k` | before the load | cap 100,000 rows | does keeping segments narrow pay, and what does the cap cost |
| `p3a_250k` | before the load | cap 250,000 rows | the same with fewer, larger segments |
| `p3a_100k_inorder` | before the load | cap 100,000, old verification | what the newest-first confirmation of long keywords is worth |
| `wide` | after the load | none | what a customer gets adding an index to an existing table |
| `rewrite` | after the load | cap 100,000 + rewrite | whether the rewrite repairs it, and what it costs |

Every index was asked the same questions for 120 s each, 20 rows per page, 10,000 queries per
second offered with 64 in flight: the two-character keyword ordered newest-first (page 1), the
same at a page half-way down the results (a cursor at the median `register_time`), the
one-character keyword, and the four-character keyword. The `wide` and `rewrite` indexes were
asked three of the four.

### Ingestion and build

| | |
|---|---|
| Four indexes caught up with the load | 15 s after the last row, all four alike |
| Index size per name | 34.7 bytes (`default`), 35.8 bytes (cap 100k), 35.3 bytes (cap 250k) |
| Full-scan build of 10M names after the load | 136 s (`wide`), 166 s (`rewrite`) |
| The rewrite of all 10M rows | 5 min: 100 slices, one every 3 s, each row read from the store and re-indexed once |

The cap costs nothing on ingestion and 3% of index size. The layouts it produced: `default` had
16 segments spanning 10.9% of the time range on average and 35.8% at worst; cap 100k had 100
segments of exactly 1% each; cap 250k had 41 segments of 3.1% on average. The `wide` build had
23 segments each spanning 100%; after the rewrite, 126 of its segments spanned 1% each.

### Throughput and index work per query

Throughput is what `latte` achieved against the 10,000 offered; the walk is the Vector Store's
own count of microseconds spent in the index per query, which is what separates the index's
cost from ScyllaDB's constant 20-row fetch (see "Where the ceiling is" above). Phases that
reached the offered rate had a client p99 between 12 and 104 ms; a phase that fell short queues
without bound in `latte`, so its p99 says nothing and is not printed.

| index | 2-char, page 1 | 2-char, deep page | 1-char | 4-char |
|---|---|---|---|---|
| `default` | 10.0k/s, 57 µs | **8.5k/s, 402 µs** | 10.0k/s, 76 µs | 10.0k/s, 118 µs |
| `p3a_100k` | 10.0k/s, 91 µs | 9.5k/s, 92 µs | 9.9k/s, 113 µs | 10.0k/s, 134 µs |
| `p3a_250k` | 10.0k/s, 44 µs | 9.5k/s, 162 µs | 10.0k/s, 51 µs | 10.0k/s, 116 µs |
| `p3a_100k_inorder` | 9.8k/s, 95 µs | 9.7k/s, 78 µs | 10.0k/s, 117 µs | **5.5k/s, 667 µs** |
| `wide` | **1.5k/s, 2.6 ms** | **0.9k/s, 4.2 ms** | **1.1k/s, 3.6 ms** | not run |
| `rewrite` | 9.9k/s, 75 µs | 9.3k/s, 136 µs | 10.0k/s, 94 µs | not run |

What each difference says:

- **Narrow segments make deep pages cheap.** The `default` index is the only one under target on
  a deep page: 402 µs against 92 µs with the cap, because a deep page on a wide segment scans
  40,000 postings where a narrow one scans 3,000. Both caps meet the target; 250k gives cheaper
  first pages (fewer segments to consider), 100k gives cheaper deep pages (a smaller segment to
  scan). The cost of the cap is the per-query bookkeeping of considering 100 segments instead of
  16, visible as 91 µs against 57 µs on page 1, and well inside the budget.
- **Confirming long keywords newest-first is worth four times.** Same index, same layout, same
  207 candidates per query: 40 stored names read instead of 223, 134 µs instead of 667, and
  10,000 queries per second instead of 5,500. This was the one shape below target before.
- **An index added to a loaded table is unusable for ordered queries until it is rewritten.** On
  the `wide` build every query scans 300,000 postings and runs at 1,500 per second; the same
  build with the cap and the rewrite answers at 9,900. The repair took five minutes for 10M rows
  and ran while no queries were being served.
- **What the run also found.** The rewrite's main pass converged, but the sparse remains of the
  last slices produced follow-up passes that never ended: the index kept re-planning small jobs
  during the `rewrite` round, so its numbers above carry that background work and four small
  chunks still spanning half the range. The cause (a slice of time cut by row count over sparse
  rows can be very wide) is fixed on the branch and covered by unit tests, but not re-measured
  at 10M.

### Names and keywords of 1 to 32 characters

The requirement is names of 1 to 32 characters and keywords of 1 to 32 characters. The corpus
of the runs above has names of 2 to 10 characters (the stage-1 table used to say 1–32, which
was the generator's cap, not what it produced), so a second corpus was generated with
`--long-names`: the same names, except that a tenth of them are 11 to 32 characters long, plus
keyword sets of 8, 16 and 32 characters, each cut from the middle of a different long name so
that it matches that name and rarely another. One run on 2026-09-28 (run
`20260928-060523-995775`, same cluster shape, the 100k cap, 10,000 queries per second offered):

| | |
|---|---|
| Index caught up with the load | 15 s after the last row, as with short names |
| Index size per name | **49.8 bytes**, against 35.8 with short names: +39% for a tenth of the names being long |

| keyword | queries/s | walk µs | segments opened | postings scanned | stored names read |
|---|---|---|---|---|---|
| 2 characters, page 1 | 10.0k | 92 | 1 | 4,849 | 20 |
| 2 characters, deep page | 10.0k | 112 | 1 | 4,841 | 20 |
| 1 character | 10.0k | 119 | 1 | 8,017 | 20 |
| 4 characters | 9.8k | 158 | 1 | 469 | 40 |
| **8 characters** | **5.0k** | **750** | **100** | 3 | 6 |
| **16 characters** | **2.3k** | **1,688** | **100** | 1 | 2 |
| **32 characters** | **1.1k** | **3,641** | **100** | 1 | 2 |
| 8 characters, deep page | 9.2k | 370 | 50 | 2 | 4 |

Name length costs nothing on ingestion and 39% on index size. Keyword length is a different
story, and not the one the design expected. Up to 4 characters nothing changes. From 8
characters up, a keyword matches fewer names than a page holds, so the walk can never stop
early: it opens every one of the 100 segments and in each looks up all of the keyword's grams
and intersects them, only to find nothing. The postings scanned and names read are tiny; the
time is per-segment overhead on segments that hold no match, about 120 µs per gram of the
keyword across the 100 segments, linear in keyword length. A deep page halves it because half
the segments lie above the cursor. This is a consequence of the cap: the same keyword on the
16-segment default layout would cost a sixth of it, which is the trade the cap makes.

The fix, not yet implemented: a map per index from each 3-character gram to the set of segments
that contain it, rebuilt on every reload from the segments' term dictionaries (a million grams
times 100 bits, a few megabytes). A keyword past `max_gram` intersects its grams' sets first and
opens only the segments that survive: three segments for a keyword matching three names instead
of a hundred, which should bring the 32-character case from 3.6 ms to under 100 µs. The
short-keyword path is untouched.

### Reproducing

The stage-2 plan is `data_dir/latte/substring_search/aws_variants_config.yaml`:

```sh
cd scylla-cluster-tests
export SCT_ENABLE_ARGUS=false
export SCT_UNIFIED_PACKAGE=<presigned url of the scylla unified tarball built from the stage-3 branch>
export SCT_SEARCH_TEST_CONFIG=data_dir/latte/substring_search/aws_variants_config.yaml
./docker/env/hydra.sh run-test substring_test.SubstringSearchTest.test_substring_search \
    --backend aws --config test-cases/substring-search/substring-search-test.yaml
```

About 3 h 40 min end to end. The `names_10M_backfill` dataset is the same corpus under a second
name (`ln -s names_10M data_dir/latte/substring_search/names_10M_backfill`), so that the two
after-the-load indexes get a load of their own.

## Known limits of the branch (stage 3)

Ordering, the range, paging, the segment cap and the rewrite are in; what follows is what is
not, or not yet measured.

- **Ordered queries are fast only with the segment cap on, and an index added to a loaded table
  only after its rewrite.** Both are opt-in placeholders today (`poc_option_2`, `poc_option_3`)
  with no real names, no defaults, and no guidance on the cap beyond the two values measured
  above. The rewrite runs in the background one slice every three seconds, with no way to pause
  it, watch it other than `/metrics`, or hurry it; and its follow-up passes over the last slices
  looped on the 10M run, a fix that is on the branch but not re-measured at that size.
- **Rare long keywords miss the target on a capped index.** A keyword of 8 characters or more
  matches fewer names than a page, so the walk opens all 100 segments and pays the gram lookups
  in each: 5.0k queries per second at 8 characters, 1.1k at 32 (see above). A gram-to-segments
  map is the fix; until it is in, the cap trades long-keyword throughput for deep-page cost.
- **The rewrite's range-width fix is not re-measured at 10M.** The run meant to do it was lost
  to a network outage on the runner's side; the in-process reproduction passes.
- **Rows sharing a sort value come highest internal id first, which is not a CQL order.** The
  cursor names the last row's primary key, so a page boundary among tied rows loses nothing
  (stage 4); but the order among the tied rows is the index node's, can change when the index
  is rebuilt, and a cursor whose row was deleted meanwhile returns the tied rows again rather
  than skip any. A client that must not see a repeat dedupes on the primary key.
- **Only the one column the index was created with**, `ASC` or `DESC` (stage 4). Stage 4 has
  passed the 3000-name docker smoke (2026-09-28, run `8247ff98`: every shape with zero errors,
  ground truth held, ascending and windowed pages full, prefix and suffix pages smaller than
  containment as expected) and is not measured at 10M.
- **The list of orderable types is written twice** (ScyllaDB checks it at `CREATE INDEX`, the node
  when it takes the index), and a disagreement refuses an index. The sort-key encoding itself is
  no longer duplicated: since stage 4 a range bound travels as a value of the column and the
  node encodes it, so nothing outside the node can misorder a result.
- One column per index and one `LIKE` per query. Searching nickname and username at once is two
  queries merged by the application, or a later multi-column index.
- `%keyword%`, `keyword%` and `%keyword` are served (stage 4: the index marks both ends of every
  value, so a prefix or suffix is containment of the keyword with the mark). General patterns,
  with `_` or a `%` inside the keyword, keep today's `ALLOW FILTERING` behaviour.
- A containment `LIKE` combined with other restrictions is rejected even with `ALLOW FILTERING`
  (see section 8).
- A prepared `LIKE ?` bound to a non-containment pattern fails at execution rather than falling
  back to filtering, because the index was chosen when the statement was prepared.
- `case_sensitive = 'false'` lowercases with full Unicode rules on the Vector Store side; CQL has
  no case-insensitive `LIKE` to compare with, so this is documented rather than reconciled.
- Index size at scale is now measured rather than estimated: 313 MiB for 10M names at the default
  `max_gram = 3` (see above), against an earlier estimate of a few GB. The corpus was synthetic and
  low in character diversity, so a real one will index larger; `max_gram = 2` remains the knob.
