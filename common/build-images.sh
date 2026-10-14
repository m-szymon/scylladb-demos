#!/bin/bash
# Builds the local container images a demo's docker-compose.yml can run:
#   localhost/scylla-<demo>:dev        ScyllaDB from the scylladb submodule
#   localhost/vector-store-<demo>:dev  Vector Store from the vector-store submodule
# Each demo directory has a build-images.sh that calls this with its own name.
#
# A demo's compose file takes its images from SCYLLA_IMAGE and VECTOR_STORE_IMAGE. Their defaults
# are these local images while the demo needs code no published image has, and the published
# images once it does not; the local ones then still run the demo on other checkouts.
# --only builds just one of the two, for a demo that needs only one side unreleased.
#
# Usage: common/build-images.sh [--only scylla|vector-store] <demo> [scylla-source-dir] [vector-store-source-dir]
set -euo pipefail

usage="usage: $0 [--only scylla|vector-store] <demo> [scylla-source-dir] [vector-store-source-dir]"
only=
if [ "${1:-}" = --only ]; then
    only=${2:?$usage}
    case $only in scylla|vector-store) ;; *) echo "$usage" >&2; exit 1 ;; esac
    shift 2
fi
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
demo=${1:?$usage}
scylla_src=${2:-$here/../scylladb}       # the scylladb submodule
vs_src=${3:-$here/../vector-store}       # the vector-store submodule
scylla_image=localhost/scylla-$demo:dev
vs_image=localhost/vector-store-$demo:dev

if [ "$only" != scylla ]; then
    echo "== Vector Store image from $vs_src"
    podman build -t "$vs_image" \
        -f "$here/Dockerfile.vector-store" \
        --ignorefile "$here/vector-store.dockerignore" \
        "$vs_src"
fi
if [ "$only" = vector-store ]; then
    echo "== done"
    podman images | grep -E "vector-store-$demo"
    exit 0
fi

echo "== ScyllaDB image from $scylla_src"
cd "$scylla_src"
# In a git worktree the .git entry is a pointer into the main repository, which dbuild does not
# mount; packaging (cqlsh's setuptools_scm, SCYLLA-RELEASE-FILE) needs git, so mount it as well.
dbuild_args=()
if [ -f .git ]; then
    gitdir=$(sed -n 's/^gitdir: //p' .git)
    main_git=${gitdir%%/worktrees/*}
    dbuild_args=(-v "$main_git:$main_git" --)
fi
if [ ! -f build/build.ninja ] && [ ! -f build.ninja ]; then
    ./tools/toolchain/dbuild "${dbuild_args[@]}" ./configure.py --mode dev
fi
# dist-dev builds the scylla binary and the rpm packages build_docker.sh installs into the image.
./tools/toolchain/dbuild "${dbuild_args[@]}" ninja -l 5 dist-dev
./dist/docker/redhat/build_docker.sh --mode dev
archive=$(ls -t build/dev/dist/docker/scylla-* | head -1)
image_id=$(podman load -q -i "$archive" | sed -n 's/^Loaded image: //p' | head -1)
[ -n "$image_id" ] || image_id=$(podman images -q | head -1)
podman tag "$image_id" "$scylla_image"
echo "== done"
podman images | grep -E "scylla-$demo|vector-store-$demo"
