#!/bin/bash
# Waits until both indexes of the demo keyspace are SERVING in the Vector Store, i.e. their initial
# full scan of search_demo.users is done and they can answer searches.
#
# Usage: ./wait-for-indexes.sh [vector-store-url] [timeout-seconds]
set -euo pipefail

url=${1:-http://127.0.0.1:6080}
timeout=${2:-180}
indexes=(users_nickname_sub users_username_sub)

deadline=$((SECONDS + timeout))
while :; do
    pending=()
    for index in "${indexes[@]}"; do
        status=$(curl -sf "$url/api/v1/indexes/search_demo/$index/status" 2>/dev/null | sed -n 's/.*"status":"\([A-Z_]*\)".*/\1/p' || true)
        [ "$status" = "SERVING" ] || pending+=("$index=${status:-not discovered}")
    done
    if [ ${#pending[@]} -eq 0 ]; then
        echo "all ${#indexes[@]} indexes are SERVING"
        curl -s "$url/api/v1/indexes"; echo
        exit 0
    fi
    if [ $SECONDS -ge $deadline ]; then
        echo "timed out after ${timeout}s; still waiting for: ${pending[*]}" >&2
        exit 1
    fi
    echo "waiting: ${pending[*]}"
    sleep 2
done
