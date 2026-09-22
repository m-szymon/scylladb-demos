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

```sh
git checkout substring-index
git submodule update --init --recursive
```

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
