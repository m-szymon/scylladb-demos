#!/bin/bash
# Waits until the given indexes of a keyspace are SERVING in the Vector Store, i.e. their initial
# full scan of the base table is done and they can answer searches.
# Each demo directory has a wait-for-indexes.sh that calls this with its own keyspace and indexes.
#
# -n also waits until every index counts at least that many rows. Rows written after the index was
# created are not part of its full scan: they reach it through CDC, after it is already SERVING,
# and a full-text index makes them searchable (and counts them) only at its next Tantivy commit,
# up to 3 s later. A demo that creates its indexes before loading its data needs -n.
#
# Usage: common/wait-for-indexes.sh [-u vector-store-url] [-t timeout-seconds] [-n rows] <keyspace> <index>...
set -euo pipefail

url=http://127.0.0.1:6080
timeout=180
rows=0
while getopts u:t:n: opt; do
    case $opt in
        u) url=$OPTARG ;;
        t) timeout=$OPTARG ;;
        n) rows=$OPTARG ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
keyspace=${1:?usage: $0 [-u url] [-t timeout] [-n rows] <keyspace> <index>...}
shift
indexes=("$@")
[ ${#indexes[@]} -gt 0 ] || { echo "no indexes given" >&2; exit 2; }

deadline=$((SECONDS + timeout))
while :; do
    pending=()
    for index in "${indexes[@]}"; do
        reply=$(curl -sf "$url/api/v1/indexes/$keyspace/$index/status" 2>/dev/null || true)
        status=$(sed -n 's/.*"status":"\([A-Z_]*\)".*/\1/p' <<<"$reply")
        count=$(sed -n 's/.*"count":\([0-9]*\).*/\1/p' <<<"$reply")
        if [ "$status" != "SERVING" ]; then
            pending+=("$index=${status:-not discovered}")
        elif [ "${count:-0}" -lt "$rows" ]; then
            pending+=("$index=SERVING,count=${count:-0}")
        fi
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
