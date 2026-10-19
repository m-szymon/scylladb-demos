#!/bin/bash
# Builds localhost/scylla-substring:dev and localhost/vector-store-substring:dev from the scylladb and
# vector-store submodules (the pattern-index-poc branches). docker-compose.yml runs these by default;
# SCYLLA_IMAGE and VECTOR_STORE_IMAGE point it at other images.
#
# Usage: ./build-images.sh [scylla-source-dir] [vector-store-source-dir]
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$here/../common/build-images.sh" substring "$@"
