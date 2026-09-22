#!/bin/bash
# Builds the two local container images the demo's docker-compose.yml uses:
#   localhost/scylla-substring:dev        ScyllaDB from the substring-index branch checkout
#   localhost/vector-store-substring:dev  Vector Store from the substring-index branch checkout
#
# Usage: ./build-images.sh [scylla-source-dir] [vector-store-source-dir]
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scylla_src=${1:-$here/../scylladb}       # the scylladb submodule
vs_src=${2:-$here/../vector-store}       # the vector-store submodule

echo "== Vector Store image from $vs_src"
podman build -t localhost/vector-store-substring:dev \
    -f "$here/Dockerfile.vector-store" \
    --ignorefile "$here/vector-store.dockerignore" \
    "$vs_src"

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
podman tag "$image_id" localhost/scylla-substring:dev
echo "== done"
podman images | grep -E "scylla-substring|vector-store-substring"
