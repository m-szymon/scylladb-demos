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
| `pattern-index-poc-upstream` | the same on the current upstream of all three repositories, with the search ordered, paged and bounded; [how it works, one idea a page](substring-search-demo/design/README.md) |

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

## This branch: `pattern-index-poc-upstream`

ScyllaDB and the Vector Store have a `pattern_index` upstream: every `LIKE` on its column goes to
the Vector Store, which answers from an index of the short pieces of each value, in one page and
in no promised order. This branch carries the substring-search proof of concept on top of that,
on a branch in each submodule based on its upstream master of 2026-11-21:

| repository | branch | what it adds to upstream |
|---|---|---|
| vector-store | `pattern-index-poc-upstream` | an index kept in the order a query asks for (`order_by`, either direction, a range on the first column), paged by a cursor; storage kept in narrow pieces and repaired as rows arrive; a page read from the end it needs; commits written in key order; a budget of time per request; the order of partitions as an option; three classes of work on the node's threads |
| scylladb | `pattern-index-poc-upstream-split` | the index options, a statement that serves each `LIKE` from the index whose order fits it, with `ORDER BY`, a range, paging through the driver's paging state, and topping up a short page |
| scylla-cluster-tests | `pattern-index-poc-upstream` | the substring search benchmark and its plans, local and AWS |

How it works is explained one idea a page, with an example, a picture and the measurements, in
**[substring-search-demo/design](substring-search-demo/design/README.md)**. The demo itself is
[substring-search-demo](substring-search-demo/README.md). The older `pattern-index-poc` and
`substring-index*` branches are the record of the earlier stages.

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
