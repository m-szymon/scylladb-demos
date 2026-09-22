# Substring search demo: `LIKE '%keyword%'` served by an index

A small, self-contained demo of ScyllaDB's `substring-index` branch together with the Vector
Store's `substring-index` branch: the search box of a live-streaming site, where a viewer types
part of a display name and gets every account whose nickname or username contains it.

```sql
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 20;
```

No `ALLOW FILTERING`, no table scan: the column carries a `substring_index`, and the query is
answered by the Vector Store from an n-gram index of the column. Seventeen accounts, mostly CJK
nicknames with a few Latin ones. Everything runs in two local containers.

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
| `nickname` | text | `users_nickname_sub`, `substring_index` | `case_sensitive = 'false'` |
| `username` | text | `users_username_sub`, `substring_index` | `case_sensitive = 'false'` |

```sql
CREATE CUSTOM INDEX users_nickname_sub ON search_demo.users (nickname)
  USING 'substring_index' WITH OPTIONS = {'case_sensitive': 'false'};
```

The index options:

| option | default | meaning |
|---|---|---|
| `min_gram` | `1` | the shortest indexed substring, in characters; a shorter keyword is not served |
| `max_gram` | `3` | the longest indexed substring; a longer keyword is answered from its pieces and verified |
| `case_sensitive` | `true` | `true` matches like CQL `LIKE` does; `false` lowercases both the column and the keyword |

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
- `LIMIT` is mandatory and at most 1000. The index stops after that many matches.
- Nothing else in the `WHERE`, no `ORDER BY`, no `GROUP BY`, no aggregates: one `LIKE` on the
  indexed column. Result order is whatever order the index returns the keys in.
- Paging is not supported: with a page size smaller than the limit, the whole result comes in one
  page with a warning, as for the other external searches.
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
SELECT nickname, username FROM search_demo.users WHERE nickname LIKE '%将军%' LIMIT 2;
```
```
 nickname | username
----------+----------
 被禁将军 | user0017
   李将军 | user0002

(2 rows)
```

The index stops after two matches. Which two is up to the index; this stage has no ordering.

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
SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' AND username LIKE '%user%' LIMIT 20;
  -> InvalidRequest: Substring search queries support exactly one LIKE restriction, on the indexed column,
     and no other WHERE restrictions

SELECT nickname FROM search_demo.users WHERE nickname LIKE '%将军%' ORDER BY register_time DESC LIMIT 20;
  -> InvalidRequest: ORDER BY with 2ndary indexes is not supported.
```

A prefix pattern, or any pattern with a wildcard inside the keyword, is not containment: the index
steps aside and `LIKE` behaves exactly as before, `ALLOW FILTERING` and a scan. The containment
query itself is strict about its shape, so that what it promises, an index lookup, is what it does.

One limit of this stage shows in the last statement of the section: the index is chosen as soon as
the `LIKE` fits it, `ALLOW FILTERING` or not, so `account_type = 0 AND nickname LIKE '%将军%' ...
ALLOW FILTERING` is rejected with the "exactly one LIKE restriction" message rather than run as a
filtered scan. Falling back to the scan in that case is the natural next step.

## Under the hood

The Vector Store's HTTP API shows what CQL is talking to:

```sh
curl -s http://127.0.0.1:6080/api/v1/indexes
```
```json
[{"keyspace":"search_demo","index":"users_nickname_sub",
  "options":{"type":"substring","min_gram":1,"max_gram":3,"case_sensitive":false},
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
{"primary_keys":{"user_id":["e236ee35-83ee-4a12-b3cf-5205bda686c1","2a8083ad-308e-42ac-9681-b0f21282e7da",
  "7bd0df74-f528-47b7-921e-fb8a45a30208","ac195af8-6535-476f-b876-fb1cc9a96946","2f10c77a-e76a-49f7-8f5c-4646923476e6"]}}
```

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
| Rows | 10,000,000 synthetic names, CJK-heavy, 1–32 characters |
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

## Known limits of the branch (stage 1)

- No ordering and no paging: `LIMIT` is applied by the index, in the index's order. The customer's
  `ORDER BY register_time DESC` with 20 rows per page is the next stage (a sort column as an index
  option, a keyset cursor in the paging state).
- One column per index and one `LIKE` per query. Searching nickname and username at once is two
  queries merged by the application, or a later multi-column index.
- Only `%keyword%` is served. Prefix (`keyword%`) and general patterns keep today's
  `ALLOW FILTERING` behaviour; an edge n-gram option for prefixes is a later stage.
- A containment `LIKE` combined with other restrictions is rejected even with `ALLOW FILTERING`
  (see section 8).
- A prepared `LIKE ?` bound to a non-containment pattern fails at execution rather than falling
  back to filtering, because the index was chosen when the statement was prepared.
- `case_sensitive = 'false'` lowercases with full Unicode rules on the Vector Store side; CQL has
  no case-insensitive `LIKE` to compare with, so this is documented rather than reconciled.
- Index size at scale is now measured rather than estimated: 313 MiB for 10M names at the default
  `max_gram = 3` (see above), against an earlier estimate of a few GB. The corpus was synthetic and
  low in character diversity, so a real one will index larger; `max_gram = 2` remains the knob.
