# Substring search: the branches, a demo and a benchmark

Substring (infix) search in ScyllaDB: `WHERE column LIKE '%keyword%'` answered from an index
instead of a scan. The feature spans three repositories, so this branch moves the workspace's
submodule pins onto the branches that implement it, and adds the demo.

| path | branch | what it is |
|---|---|---|
| [scylladb](scylladb) | `substring-index` | the `substring_index` custom index class, the CQL routing for `LIKE '%keyword%'`, and the statement that asks the index node |
| [vector-store](vector-store) | `substring-index` | the index node: the n-gram index kind and the `/contains` endpoint |
| [scylla-cluster-tests](scylla-cluster-tests) | `substring-search-perf` | the benchmark: index size per name and query latency under load |
| [substring-search-demo](substring-search-demo) | | a runnable demo of the feature, with its own README |

Start with [substring-search-demo/README.md](substring-search-demo/README.md); it explains the
index, the query, what the branches do and do not do yet, and what the feature measured at 10M
rows on AWS. For the benchmark itself, see
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
git -C scylladb             push origin substring-index
git -C vector-store         push origin substring-index
git -C scylla-cluster-tests push origin substring-search-perf
git push origin substring-index
```

Pushing the first two is also a prerequisite of an AWS benchmark run: the index node builds
vector-store from git, and the Scylla branch has to be built into a package. See
[scylla-cluster-tests/docs/substring-search-test.md](scylla-cluster-tests/docs/substring-search-test.md).

After committing in a submodule, record the new pin here:

```sh
git add scylladb vector-store scylla-cluster-tests
git commit -m "pin: update submodules"
```
