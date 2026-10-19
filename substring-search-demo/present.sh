#!/bin/bash
# Presents the demo live: cqlsh on the running scylla container, with the statements of demo.cql
# one key press away (PgDn types the next one, pressed again runs it). See common/present.sh.
# cqlsh is the PyPI scylla-cqlsh, run by uv, without its "Failed to format value" reports
# (common/cqlsh-quiet.py).
#
# Usage: ./present.sh [sections]   e.g. ./present.sh 0-7 leaves out the guard rails of section 8
# (after the set-up steps of the README, with the containers up)
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$here/../common/present.sh" ${1:+-s "$1"} substring "$here/demo.cql" \
    uv run -q --no-project --python 3.12 --with scylla-cqlsh==6.0.39 \
    "$here/../common/cqlsh-quiet.py" 127.0.0.1 9042
