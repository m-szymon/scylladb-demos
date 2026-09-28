# Substring search: the branches, a demo and a benchmark

Substring (infix) search in ScyllaDB: `WHERE column LIKE '%keyword%'` answered from an index
instead of a scan. The feature spans three repositories, so this branch moves the workspace's
submodule pins onto the branches that implement it, and adds the demo.

| path | branch | what it is |
|---|---|---|
| [scylladb](scylladb) | `substring-index-stage2` | the `substring_index` custom index class, the CQL routing of `LIKE '%keyword%'`, `ORDER BY`, the range on the ordered column, cursor paging, and the placeholder index options |
| [vector-store](vector-store) | `substring-index-stage2` | the index node: n-gram index, ordered walk with segment pruning, the segment cap (`poc_option_2`), two-pass verification, per-query counters |
| [scylla-cluster-tests](scylla-cluster-tests) | `substring-search-perf-stage2` | the benchmark: ordered and paged query sets, index variants over one load, layout and per-query counters |
| [substring-search-demo](substring-search-demo) | | a runnable demo of every supported query, with the measurements |

This is **stage 2** of three. Stage 1 (`substring-index`, `substring-search-perf`) is
containment alone. Stage 2 adds `ORDER BY` newest-first, a range on the ordered column, cursor
paging, the segment cap that keeps deep pages cheap, and two-pass verification of long keywords.
Stage 3 (`*-stage3`) adds the background rewrite that repairs an index created on an already
loaded table, and names and keywords up to 32 characters; its superproject branch reports all
runs.

Start with [substring-search-demo/README.md](substring-search-demo/README.md): the index, the
query, what the branches do and do not do yet, and what stages 1 and 2 measured at 10M rows on
AWS. The design behind stage 2 and the measurements as they came in are in
[vector-store/docs/dev/substring/stage-2-ordering.md](vector-store/docs/dev/substring/stage-2-ordering.md).
For the benchmark itself, see
[scylla-cluster-tests/docs/substring-search-test.md](scylla-cluster-tests/docs/substring-search-test.md),
which runs from a developer machine against an AWS cluster.

## Working with the submodules

Each submodule is a checkout on the branch named above, with `origin` pointing at the fork the
branch lives on and `upstream` at the ScyllaDB repository it came from:

```sh
git submodule status                          # the pinned commit of each
git -C scylladb log --oneline -6              # five commits on top of upstream
git -C vector-store log --oneline -3          # two commits on top of upstream
git -C scylla-cluster-tests log --oneline -3  # two commits on top of the full-text search PR
```

The substring benchmark sits on top of the branch of
[scylladb/scylla-cluster-tests#15769](https://github.com/scylladb/scylla-cluster-tests/pull/15769),
which is where the shared search-benchmark flow it reuses comes from.

### Pushing

Submodules first, superproject second: a pin the forks do not have is a pin nobody else can check
out. `push.recurseSubmodules=check` is set here, so a superproject push that would dangle is
refused rather than accepted.

```sh
git -C scylladb             push origin substring-index-stage2
git -C vector-store         push origin substring-index-stage2
git -C scylla-cluster-tests push origin substring-search-perf-stage2
git push origin substring-index-stage2
```

Pushing the first two is also a prerequisite of an AWS benchmark run: the index node builds
vector-store from git, and the Scylla branch has to be built into a package. See
[scylla-cluster-tests/docs/substring-search-test.md](scylla-cluster-tests/docs/substring-search-test.md).

After committing in a submodule, record the new pin here:

```sh
git add scylladb vector-store scylla-cluster-tests
git commit -m "pin: update submodules"
```
