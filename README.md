# Substring search: the branches, a demo, a benchmark, and where it stands

Substring (infix) search in ScyllaDB: `WHERE column LIKE '%keyword%'` answered from an index on
a separate node instead of a table scan, with `ORDER BY` and paging on top. The feature spans
three repositories; this superproject pins the branches that implement it and holds the demo.
This file is the handover: what exists, what it measured, how to run it, and what is left.

## The repositories

| path | branch on the fork | what it is |
|---|---|---|
| [scylladb](scylladb) | `substring-index-stage5` | the `substring_index` custom index class, the CQL routing of `LIKE '%keyword%'` (and `'keyword%'`, `'%keyword'`), `ORDER BY` either way, the range on the ordered column, cursor paging, and the placeholder index options |
| [vector-store](vector-store) | `substring-index-stage5` | the index node: n-gram index, ordered walk with segment pruning, two-pass verification, the range merge policy (P3a), the rewrite of wide segments (P3b), metrics |
| [scylla-cluster-tests](scylla-cluster-tests) | `substring-search-perf-stage5` | the benchmark: corpus generator, plans, index variants per dataset, layout and per-query counters |
| [substring-search-demo](substring-search-demo) | | a two-container demo of every supported query, and the plain-language report of all runs |

All three forks are `m-szymon/...`; `upstream` in each checkout is the ScyllaDB repository.

## The five stages

Each stage is a set of branches (one per repository, plus a branch of this superproject that pins
them) and each contains the previous one. The names are `substring-index` / `substring-search-perf`
for stage 1, and the same with `-stage2` to `-stage5` after them.

| stage | what it added | measured |
|---|---|---|
| 1 | containment: `LIKE '%keyword%' LIMIT n` answered by the index node, any order | 2026-09-22: 9.6k queries/s, bounded by ScyllaDB's row reads |
| 2 | `ORDER BY` newest-first, a range on the ordered column, cursor paging; the segment cap (`poc_option_2`) that keeps deep pages cheap; two-pass verification of long keywords; per-query counters | 2026-09-25 (design note) and 2026-09-27 (demo README) |
| 3 | the background rewrite (`poc_option_3`) that repairs an index created on an already loaded table; names and keywords up to 32 characters | 2026-09-27 and 2026-09-28 (demo README) |
| 4 | correctness: the cursor names its row so tied sort values page without gaps, `ORDER BY ... ASC`, prefix and suffix `LIKE` | 2026-09-28: the docker smoke only (3000 names); not run at 10M |
| 5 | a keyword past `max_gram` on a case-sensitive index is checked by ScyllaDB on the rows it reads, not by the node on its stored text; range bounds travel as typed values | 2026-09-29: at 10M, run `697ea24b` long keywords +23% to +52%; run `4ce3f8b8` the A/B (no capacity difference, node verifying has the better p99 at 4 characters) and the segment skip (32 characters 7x, 16 characters 2x); 2026-09-30, run `7212926d`: the reused gram entries and the segment size sweep, every query type at 8.7k/s or more with a 200k cap (design note) |

The scylladb branch is the same commit for stages 2 and 3: stage 3 is index-node and benchmark
work only. Stage 4 changes all three again. The demo README on this branch reports every run; the stage-2 branch of this
superproject reports the runs up to its own state.

## What to read, in order

1. [substring-search-demo/README.md](substring-search-demo/README.md): the feature query by
   query, what is supported and what is refused, and the three AWS runs at 10M names with their
   numbers and conclusions. Start here.
2. [vector-store/docs/dev/substring/stage-2-ordering.md](vector-store/docs/dev/substring/stage-2-ordering.md):
   why ordering is hard for an n-gram index, the design (segment pruning, the cap, the rewrite),
   the rejected alternatives, the measurements as they came in, and the open risks.
3. [scylla-cluster-tests/docs/substring-search-test.md](scylla-cluster-tests/docs/substring-search-test.md):
   how the benchmark works, the corpora and plans, and how to run it locally and on AWS.

## Where it stands (2026-09-30)

Implemented and unit-tested on the stage-4 branches:

- Containment, prefix and suffix search (`LIKE '%kw%'`, `'kw%'`, `'%kw'` with `LIMIT n`),
  ordered `DESC` or `ASC` on one `order_by` column, a range on that column, cursor paging
  through the driver's paging state; the cursor carries the last row's primary key, so rows
  sharing a sort value page without gaps.
- Placeholder index options `poc_option_1..4` accepted by ScyllaDB and given meaning by the
  index node: `poc_option_2` a row cap per segment (the range merge policy), `poc_option_3`
  the background rewrite of wide segments, `poc_option_4` the old single-pass verification
  (for A/B only), `poc_option_1` a FAST primary id (measured useless).

Measured at 10M names on AWS (i4i.xlarge Scylla, 4-core c8g.xlarge index node, 20 rows a page):

- Short keywords, any page, on a capped index: 10k queries/s at under 100 us in the index.
  The cap is what makes deep pages cheap (402 us on the default layout, 92 us with the cap).
- Long keywords (past `max_gram`): two-pass verification takes 4 characters from 5.5k/s to 10k/s.
- An index created on a loaded table is unusable for ordered queries (1.5k/s) until the rewrite
  repairs it (9.9k/s); the rewrite of 10M rows took five minutes.
- Rare long keywords (stage 5, 2026-09-29): the segment skip checks each segment's term
  dictionary for the keyword's grams before opening it. It took 32 characters from 1.7k/s to
  11.9k/s and 16 characters from 2.8k/s to 5.9k/s.
- Segment size (2026-09-30, run `7212926d`, with the check's gram entries reused when a
  segment is opened): with a cap of 200k rows a segment every query type runs at 8.7k/s or
  more. The weakest is 16 characters at 8.7k. 8 characters reaches 12.1k and 32 characters
  10.3k. The 100k cap leaves 8 and 16 characters at 7.5-7.9k, and the 400k cap drops
  1 character to 7.5k.
- The ~9.7k/s ceiling for 1-4 characters is ScyllaDB reading the 20 rows of a full page
  (about 195k rows a second on one i4i.xlarge), not the index. Rare keywords go above it
  because they have fewer matches than a page in the whole table (about 1-2.4 rows), and
  there the index node is the limit.
- Where verification runs (`verify_candidates`) makes no difference to capacity. At 4
  characters ScyllaDB verifying halves the node's work but raises p99 from 1.9 to 4.7 ms. p99
  at a fixed rate below capacity is 1.7-4.7 ms for every keyword length.
- **Open:** the rewrite's last-slices fix (`vector-store` commit `a6cfcf7`) is reproduced
  in-process and not re-measured at 10M; the run meant to do it was lost to a network outage.

Stage 4 (2026-09-28) passed the docker smoke at 3000 names: every query shape ran with zero
errors, ground truth held for 4-, 16- and 32-character keywords, ascending pages were full,
prefix and suffix pages were smaller than containment pages as expected, and the rewrite
repaired the shuffled index (31 segments, 60 ranges). The smoke does not check the returned
order itself; that is covered by the vector-store unit tests and the ScyllaDB cqlpy tests
against the mock. Stage 4 is not measured at 10M.

Raw results of every run are on the laptop the runs were driven from, under
`~/sct-results/<timestamp>/`, with each result row in the `argus_replay_log_*.jsonl` file there.
The run ids are quoted in the demo README.

## What is left, in the order I would do it

1. Done 2026-09-29 and 2026-09-30 (runs `4ce3f8b8` and `7212926d`): the A/B of where
   verification runs, the segment skip, the reused gram entries and the segment size sweep.
   What stays open: 16 characters is the weakest query type at 8.7k/s (a cap between 200k and
   400k may balance it against 1 character), and letting the node choose per query where
   verification runs.
2. The default `verify_candidates`: the measurements favour the node verifying (same capacity,
   better p99 at 4 characters). Decide whether to flip the default before the per-query choice
   exists.
3. The rewrite at 10M is still unmeasured: the 2026-09-29 run stopped at the end of the
   backfill's full scan when the runner lost the nodes for a minute. The index node's logs
   are collected now. Consider driving long runs from an AWS runner. After
   that, drop the stored text from the index and measure the size.
4. Real names and defaults for the options instead of `poc_option_N`: the cap on by default
   whenever `order_by` is set (200k, from the 2026-09-30 sweep), the rewrite on by default.
5. General `LIKE` patterns (`_`, a `%` inside the keyword), which stay on `ALLOW FILTERING`
   today. (The tie-break cursor, `ASC`, and typed range bounds so that the sort-key encoding
   lives on the node only are done in stage 4.)
6. Unmeasured behaviour: a rewrite under a steady stream of writes, queries during a rewrite,
   index size on a real corpus with a wide character set.
7. Splitting the branches into reviewable pull requests.

## Running things

**The demo** (two local containers, 17 rows): see the demo README's set-up section.

**The docker smoke** (3000 names, checks correctness with ground truth, 15 min):

```sh
cd scylla-cluster-tests
python3 data_dir/latte/substring_search/generate_local_dataset.py --dataset local_tiny --names 3000 --shards 3 --long-names
python3 data_dir/latte/substring_search/generate_local_dataset.py --dataset local_ingest --names 3000 --shards 3 --long-names
python3 data_dir/latte/substring_search/generate_local_dataset.py --dataset local_shuffled --names 3000 --shards 3 --sort-order shuffled --long-names
SCT_ENABLE_ARGUS=false SCT_SEARCH_TEST_CONFIG=data_dir/latte/substring_search/local_config.yaml \
  ./docker/env/hydra.sh run-test substring_test.SubstringSearchTest.test_substring_search \
  --backend docker --config test-cases/substring-search/substring-search-test-docker.yaml
```

It needs the real docker daemon (rootless podman cannot reach the node containers), a Scylla
image built from the branch, and a vector-store image built from the branch and loaded into
docker as `localhost/vector-store-substring:dev` (a two-stage build: `rust:1.97-bookworm`
running `cargo build --release --bin vector-store`, copied into `debian:bookworm-slim`, port 6080).

**An AWS run** (2 to 4 hours, one Okta session): the SCT doc has the full procedure. The parts
that cost failed launches to learn:

- Always `SCT_ENABLE_ARGUS=false`; from an unpushed branch Argus rejects the run and the test
  then fails on its first result.
- The Scylla package is a relocatable tarball in the private bucket
  `s3://full-text-search-sct/substring/`; presign it with `--region us-east-1` (the bucket's
  region) and pass the URL as `SCT_UNIFIED_PACKAGE`; verify with a ranged GET, not HEAD.
- The index node builds vector-store from the fork: `vector_store_source_ref` in
  `test-cases/substring-search/substring-search-test.yaml` names the branch, which must be pushed.
- The test case destroys every node on any outcome. If the runner dies with the run (network
  drop, laptop asleep), terminate by hand:
  `SCT_REGION_NAME=eu-west-1 SCT_CLUSTER_BACKEND=aws ./docker/env/hydra.sh clean-resources --test-id <id>`
  and check with `aws ec2 describe-instances --filters Name=tag:TestId,Values=<id>*`.
- Run it under `systemd-inhibit --what=sleep:idle` on a laptop; a suspend or a lost connection
  wedges the runner on its SSH session.
- The backfill datasets are the sequential corpus under another name:
  `ln -s names_10M data_dir/latte/substring_search/names_10M_backfill` (and the same for
  `names_10M_long`). The corpora are generated, not committed.

## Working with the submodules

Each submodule is a checkout on the branch named above. Push submodules first, the superproject
second; `push.recurseSubmodules=check` refuses a superproject push whose pins the forks lack:

```sh
git -C scylladb             push origin substring-index-stage5
git -C vector-store         push origin substring-index-stage5
git -C scylla-cluster-tests push origin substring-search-perf-stage5
git push origin substring-index-stage5
```

After committing in a submodule, record the new pin here:

```sh
git add scylladb vector-store scylla-cluster-tests
git commit -m "Bump submodules: ..."
```
