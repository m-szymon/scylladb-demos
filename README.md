# ScyllaDB demos

A workspace for demos that span more than one ScyllaDB repository. Each demo needs a matching
checkout of several repositories at once, so this superproject pins them together as submodules
and each demo lives on its own branch.

| path | what it is |
|---|---|
| [scylladb](scylladb) | the database |
| [vector-store](vector-store) | the index node that serves vector, full-text and substring search |
| [scylla-cluster-tests](scylla-cluster-tests) | SCT, the test and benchmark harness |

On `main` the three are pinned at upstream commits with no demo work in them, so this branch is
only the scaffold. Check out a demo branch for the demo itself:

| branch | what it adds |
|---|---|
| `substring-index` | substring (infix) search: `WHERE column LIKE '%keyword%'` answered from an n-gram index instead of a scan, with a runnable demo and an AWS benchmark |
| `hybrid-search` | hybrid search: one `SELECT` ordered by several vector (ANN) and full-text (BM25) searches fused with RRF, with highlighting, as a runnable demo ([scylladb/scylladb#31580](https://github.com/scylladb/scylladb/pull/31580), merged) |

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

## Layout

Each demo is a directory `<name>-demo/` on its branch: the CQL, a `docker-compose.yml`, a README
with the walkthrough, and thin `build-images.sh` and `wait-for-indexes.sh` wrappers. What the
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
