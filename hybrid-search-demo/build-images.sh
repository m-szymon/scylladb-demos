#!/bin/bash
# Builds localhost/scylla-hybrid:dev and localhost/vector-store-hybrid:dev from the scylladb and
# vector-store submodules. docker-compose.yml runs published images by default; SCYLLA_IMAGE and
# VECTOR_STORE_IMAGE point it at these instead.
#
# Usage: ./build-images.sh [scylla-source-dir] [vector-store-source-dir]
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$here/../common/build-images.sh" hybrid "$@"
