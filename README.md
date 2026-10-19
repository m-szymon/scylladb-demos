# ScyllaDB demos

A workspace for demos that span more than one ScyllaDB repository. Each demo needs a matching
checkout of several repositories at once, so this superproject pins them together as submodules.
A demo on code that is not upstream yet lives on its own branch; once its code is merged and
published, it moves to `main` and runs on the published images.

| path | what it is |
|---|---|
| [scylladb](scylladb) | the database |
| [vector-store](vector-store) | the index node that serves vector, full-text and substring search |
| [scylla-cluster-tests](scylla-cluster-tests) | SCT, the test and benchmark harness |

On `main` the three are pinned at upstream commits, with the demos whose code is all upstream:

| demo | what it shows |
|---|---|
| [hybrid-search-demo](hybrid-search-demo) | hybrid search: one `SELECT` ordered by several vector (ANN) and full-text (BM25) searches fused with RRF, with highlighting ([scylladb/scylladb#31580](https://github.com/scylladb/scylladb/pull/31580)) |

Check out a demo branch for a demo on code that is not upstream yet:

| branch | what it adds |
|---|---|
| `substring-index` | substring (infix) search: `WHERE column LIKE '%keyword%'` answered from an n-gram index instead of a scan, with a runnable demo and an AWS benchmark |
| `substring-index-stage2` .. `-stage5` | the same proof of concept, stage by stage: ordering, paging, segment balancing, verification; the record of the AWS runs |
| `pattern-index-poc` | the proof of concept moved onto the `pattern_index` that ScyllaDB now has upstream (see below) |

```sh
git checkout substring-index
git submodule update --init
# scylladb names its own submodules relative to its origin, the fork, which has none of them
# but seastar; point them at the ScyllaDB repositories before fetching them.
git -C scylladb submodule init
git -C scylladb config --get-regexp '^submodule\..*\.url$' | grep m-szymon |
    while read -r key url; do git -C scylladb config "$key" "${url/m-szymon/scylladb}"; done
git submodule update --init --recursive
```

The URLs are set once per clone, in `scylladb`'s own config. A demo branch whose scylladb adds a
submodule needs the loop run again, or `git submodule update` fails to clone it from the fork.

## This branch: `pattern-index-poc`

ScyllaDB master has `pattern_index`, which sends any `LIKE` on its column to the Vector Store's
`/like` with the pattern as written, in one unordered page. The Vector Store master indexes the
values as framed 1-3 character n-grams, on tantivy code it shares with full-text search, but does
not answer `/like` yet. This branch carries the substring-search proof of concept (the
`substring-index*` branches) onto those, on a `pattern-index-poc` branch in each submodule, based on
its upstream master (scylla-cluster-tests: on the full-text benchmark it extends, see below):

| repository | what the branch adds to upstream |
|---|---|
| vector-store | `/like` on the upstream index: the node reads the pattern with ScyllaDB's `LIKE` rules and serves `'%kw%'`, `'kw%'` and `'%kw'`; the n-gram sizes and case folding as options; with `order_by`, ordering, ranges and cursor paging; the segment cap and the rewrite; the segment skip; verification that a caller may decline. The shared tantivy code gains what that needs: per-index state, its own documents and merge policy, and a reload on demand |
| scylladb | the options (`order_by`, `min_gram`, `max_gram`, `segment_rows`, `rewrite`, `verify_candidates`), and a statement for an index with `order_by`: `ORDER BY` on that column, a range on it, paging through the driver's paging state, the LIMIT rules, and verification by ScyllaDB's own `LIKE` when asked; the index depends on its `order_by` column, so that column cannot be dropped or renamed while the index exists |
| scylla-cluster-tests | the full-text and substring search benchmarks, the latter on `pattern_index` with the new option names; based on upstream master of 2026-10-15, since the open full-text benchmark PRs it builds on (#15719, #15769) are not rebased yet |

The option names replace the placeholders of the proof of concept: `segment_rows` (was
`poc_option_2`, 200000 by default with `order_by`) and `rewrite` (was `poc_option_3`, on wherever
there is a cap); the node verifies by default. The measurements in
[substring-search-demo/README.md](substring-search-demo/README.md) were taken on the
`substring-index*` branches; the port is not measured yet.

## Layout

Each demo is a directory `<name>-demo/`, on `main` or on its branch: the CQL, a `docker-compose.yml`, a README
with the walkthrough, and thin `build-images.sh`, `wait-for-indexes.sh` and `present.sh` wrappers. What the
wrappers call lives in [common](common) and is the same for every demo.

A demo's `docker-compose.yml` takes its images from `SCYLLA_IMAGE` and `VECTOR_STORE_IMAGE`. While
the demo needs code no published image has, the default is the local image `build-images.sh` builds
from the submodule; once the code is published (a nightly is enough), the default becomes that
image, pinned by tag, with the submodule pinned on the same commit. Either side can be on its own:
`--only` builds just one.



| file | what it does |
|---|---|
| [common/build-images.sh](common/build-images.sh) | `[--only scylla\|vector-store] <demo> [scylla-src] [vector-store-src]`: builds `localhost/scylla-<demo>:dev` and `localhost/vector-store-<demo>:dev` from the submodules |
| [common/Dockerfile.vector-store](common/Dockerfile.vector-store), [common/vector-store.dockerignore](common/vector-store.dockerignore) | the Vector Store image |
| [common/wait-for-indexes.sh](common/wait-for-indexes.sh) | `[-u url] [-t timeout] <keyspace> <index>...`: waits until the Vector Store serves every listed index |
| [common/cqlsh-quiet.py](common/cqlsh-quiet.py) | cqlsh without its `Failed to format value` reports, for `present.sh`; run with `uv run --with scylla-cqlsh` |
| [common/present.sh](common/present.sh) | `<demo> <cql-file> <cqlsh-command>...`: cqlsh in a tmux session of its own, PgDn typing and then running the file's next statement, for presenting a demo live |

The demos all publish ports 9042 and 6080, so run one at a time: `podman-compose down -v` in one
before `up` in another.

## Working with the submodules

Each submodule has `origin` on the fork the demo branches live on and `upstream` on the ScyllaDB
repository it came from, which is what a recursive clone of this superproject produces.

```sh
git submodule status              # the pinned commit of each
git -C scylladb remote -v         # origin = the fork, upstream = scylladb/scylladb
```

`scylla-cluster-tests` is pinned on the branch of
[scylladb/scylla-cluster-tests#15769](https://github.com/scylladb/scylla-cluster-tests/pull/15769)
rather than on master, because the shared search-benchmark flow the demos reuse comes from there
and is not upstream yet.

## Pushing

Submodules first, superproject second: a pin the forks do not have is a pin nobody else can check
out. `push.recurseSubmodules=check` is set here, so a superproject push that would dangle is
refused rather than accepted.

```sh
git -C scylladb push origin <branch>   # and the same for the other submodules
git push origin <branch>
```
