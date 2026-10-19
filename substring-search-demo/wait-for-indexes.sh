#!/bin/bash
# Waits until both indexes of the demo keyspace are SERVING in the Vector Store and count all
# 17 rows of search_demo.users. schema.cql creates the indexes before data.cql loads the rows, so
# the rows reach them through CDC after they are already SERVING.
#
# Usage: ./wait-for-indexes.sh [vector-store-url] [timeout-seconds]
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$here/../common/wait-for-indexes.sh" -u "${1:-http://127.0.0.1:6080}" -t "${2:-180}" -n 17 \
    search_demo users_nickname_sub users_username_sub
