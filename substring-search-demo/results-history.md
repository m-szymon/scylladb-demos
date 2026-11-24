# Substring search: the record of the earlier measurements

These sections were in the demo's README while the proof of concept grew, stage by stage. They
are kept as they were written, as the record of what was measured and when. Branch names, option
names and commit ids in them are of their time: the index was called `substring_index`, and the
stages lived on the `substring-index*` branches.

For how the search works today and the current numbers, see [design/](design/README.md).

## Performance at 10M rows

The runs from here on were made on the proof of concept before it moved onto `pattern_index`, on
the `substring-index*` branches: the index was `substring_index`, the endpoint `/contains`, and the
segment cap and the rewrite were the placeholders `poc_option_2` and `poc_option_3`, now
`segment_rows` and `rewrite`. The mechanisms measured are the ones the port carries; the port
itself is not measured yet.

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

The fix as designed then (stage 5 built a simpler one, the segment skip below): a map per index from each 3-character gram to the set of segments
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

## Performance at 10M rows, stage 5: where verification runs, and the segment skip (2026-09-29)

Run `4ce3f8b8`, plan `aws_stage5_ab_config.yaml`, the same machines, names of 1 to 32
characters, 20 rows a page, newest first. Two case-sensitive indexes on one table, both capped at
100k rows a segment. On one the node verifies long keywords (`verify_candidates: 'index'`). On the
other ScyllaDB verifies them on the rows it reads, which is the default. Every query set was
measured once without a rate limit, for capacity, and once at a fixed rate below capacity, so
that p99 describes a query rather than the loader's queue.

| keyword | q/s, ScyllaDB verifies | q/s, node verifies | p99 below capacity, ScyllaDB / node |
|---|---|---|---|
| 1 char | 9,578 | 10,100 | |
| 2 chars | 9,381 | 9,406 | 1.8 / 1.7 ms at 2,000/s |
| 4 chars | 8,597 | 8,783 | 4.7 / 1.9 ms at 2,000/s |
| 8 chars | 5,457 | 5,615 | 3.5 / 3.4 ms at 2,000/s |
| 8 chars, older half | 10,275 | 10,436 | |
| 16 chars | 5,874 | 5,850 | 4.3 / 4.0 ms at 1,000/s |
| 32 chars | 11,913 | 11,484 | 2.4 / 2.8 ms at 500/s |

- Where verification runs does not change capacity. At 4 characters ScyllaDB verifying halves
  the index node's work, but its short pages need top-ups, which raises p99.
- The segment skip (each segment's term dictionary is checked for the keyword's grams before the
  segment is opened) took 32 characters from 1.7k to 11.9k q/s and 16 characters from 2.8k to
  5.9k, against run `697ea24b` the same morning.
- 8 and 16 characters over the whole range stay near 6k q/s. The index node's CPU is the limit
  (about 650 us a query on 4 cores), because many segments hold every gram of such a keyword
  without holding a match.

Details and per-query index counters: the stage-5 sections of
`vector-store/docs/dev/substring/stage-2-ordering.md`.

## Performance at 10M rows, stage 5: segment size (2026-09-30)

Run `7212926d`, plan `aws_segment_size_config.yaml`. Three case-sensitive indexes on one table
differ only in the cap: 100k, 200k and 400k rows a segment (107, 51 and 26 segments). All three
verify on the node and run with a segment's gram postings built from the entries the segment skip
already found. Capacity in queries per second:

| keyword | cap 100k | cap 200k | cap 400k |
|---|---|---|---|
| 1 char | 9,900 | 9,973 | 7,522 |
| 2 chars | 9,680 | 9,731 | 9,597 |
| 4 chars | 9,258 | 9,737 | 9,717 |
| 8 chars | 7,864 | 12,094 | 18,732 |
| 16 chars | 7,538 | 8,661 | 11,520 |
| 32 chars | 13,357 | 10,282 | 9,083 |

- **The 200k cap is the flattest.** Every query type is at 8.7k or more.
- **Larger segments trade the two ends.** They help rare long keywords, because fewer segments are
  opened. They cost the commonest keyword, whose posting lists get longer, and 32 characters,
  whose ~30 grams are more often all present in a large segment.
- **The ~9.7k ceiling for 1 to 4 characters is ScyllaDB reading a full page of 20 rows.** Rare
  keywords go above it because the whole table holds only 1 to 2.4 matching names, so their
  pages are complete but short.
- **p99 below capacity** was 1.6 to 3.4 ms everywhere.

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
- **A long keyword on a case-insensitive index is still verified on the node** (stage 5 moves
  that check to ScyllaDB for case-sensitive indexes only, because the node's Unicode case
  folding is not something ScyllaDB can repeat exactly). Such an index pays a document-store
  read per candidate for keywords past `max_gram`, as before.
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
