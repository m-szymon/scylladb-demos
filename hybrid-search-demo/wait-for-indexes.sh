#!/bin/bash
# Waits until all four indexes of the demo keyspace are SERVING in the Vector Store and count all
# eight rows of demo.articles. schema.cql creates the indexes before data.cql loads the rows, so the
# rows arrive through CDC after SERVING, and the full-text indexes count them only at their next
# commit, up to 3 s later.
#
# Usage: ./wait-for-indexes.sh [vector-store-url] [timeout-seconds]
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$here/../common/wait-for-indexes.sh" -u "${1:-http://127.0.0.1:6080}" -t "${2:-180}" -n 8 \
    demo articles_title_fts articles_body_fts articles_title_ann articles_body_ann
