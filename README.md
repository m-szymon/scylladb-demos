# Substring search: the branches, a demo, a benchmark, and where it stands

Substring (infix) search in ScyllaDB: `WHERE column LIKE '%keyword%'` answered from an index on
a separate node instead of a table scan, with `ORDER BY` and paging on top. The feature spans
three repositories; this superproject pins the branches that implement it and holds the demo.
This file is the handover: what exists, what it measured, how to run it, and what is left.

## The repositories

| path | branch on the fork | what it is |
|---|---|---|
| [scylladb](scylladb) | `substring-index-stage4` | the `substring_index` custom index class, the CQL routing of `LIKE '%keyword%'` (and `'keyword%'`, `'%keyword'`), `ORDER BY` either way, the range on the ordered column, cursor paging, and the placeholder index options |
| [vector-store](vector-store) | `substring-index-stage4` | the index node: n-gram index, ordered walk with segment pruning, two-pass verification, the range merge policy (P3a), the rewrite of wide segments (P3b), metrics |
| [scylla-cluster-tests](scylla-cluster-tests) | `substring-search-perf-stage4` | the benchmark: corpus generator, plans, index variants per dataset, layout and per-query counters |
| [substring-search-demo](substring-search-demo) | | a two-container demo of every supported query, and the plain-language report of all runs |

All three forks are `m-szymon/...`; `upstream` in each checkout is the ScyllaDB repository.

## The four stages

Each stage is a set of branches (one per repository, plus a branch of this superproject that pins
them) and each contains the previous one. The names are `substring-index` / `substring-search-perf`
for stage 1, and the same with `-stage2`, `-stage3` and `-stage4` after them.

| stage | what it added | measured |
|---|---|---|
| 1 | containment: `LIKE '%keyword%' LIMIT n` answered by the index node, any order | 2026-09-22: 9.6k queries/s, bounded by ScyllaDB's row reads |
| 2 | `ORDER BY` newest-first, a range on the ordered column, cursor paging; the segment cap (`poc_option_2`) that keeps deep pages cheap; two-pass verification of long keywords; per-query counters | 2026-09-25 (design note) and 2026-09-27 (demo README) |
| 3 | the background rewrite (`poc_option_3`) that repairs an index created on an already loaded table; names and keywords up to 32 characters | 2026-09-27 and 2026-09-28 (demo README) |
| 4 | correctness: the cursor names its row so tied sort values page without gaps, `ORDER BY ... ASC`, prefix and suffix `LIKE` | 2026-09-28: the docker smoke only (3000 names); not run at 10M |

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

## Where it stands (2026-09-28)

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
- **Open:** a keyword of 8 characters or more matches fewer names than a page, so the walk opens
  every segment the cap made and pays the gram lookups in each: 5.0k/s at 8 characters, 1.1k/s
  at 32. The fix is designed (a per-index map from gram to the segments containing it), not
  built. This is the first thing to do.
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

1. The gram-to-segments map for rare long keywords, then one AWS run of
   `aws_followup_config.yaml` (about 2 h 20 min) which also re-measures the rewrite fix.
2. Real names and defaults for the options instead of `poc_option_N`: the cap on by default
   whenever `order_by` is set (100k), the rewrite on by default.
3. Typed values in the request so the sort-key encoding exists in one place instead of two
   (the tie-break cursor and `ASC` are done in stage 4). General `LIKE` patterns (`_`, a `%`
   inside the keyword) stay on `ALLOW FILTERING`.
4. Unmeasured behaviour: a rewrite under a steady stream of writes, queries during a rewrite,
   index size on a real corpus with a wide character set.
5. Splitting the branches into reviewable pull requests.

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
git -C scylladb             push origin substring-index-stage4
git -C vector-store         push origin substring-index-stage4
git -C scylla-cluster-tests push origin substring-search-perf-stage4
git push origin substring-index-stage4
```

After committing in a submodule, record the new pin here:

```sh
git add scylladb vector-store scylla-cluster-tests
git commit -m "Bump submodules: ..."
```
