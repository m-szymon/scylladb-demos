#!/bin/bash
# Builds localhost/scylla-hybrid:dev and localhost/vector-store-hybrid:dev, the images
# docker-compose.yml uses, from the scylladb and vector-store submodules.
#
# Usage: ./build-images.sh [scylla-source-dir] [vector-store-source-dir]
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$here/../common/build-images.sh" hybrid "$@"
