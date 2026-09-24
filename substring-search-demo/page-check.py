#!/usr/bin/env python3
"""Prints the pages of an ordered substring search as they arrive.

cqlsh's PAGING shows the rows but not the page boundaries, and the boundaries are the point: each
page tells the index node where the last one stopped, so the walk resumes rather than restarting.
This runs the same query through the driver and prints one line per page.

Usage: page-check.py [host]   (default: the demo's published port on localhost)
"""

import sys

from cassandra.cluster import Cluster
from cassandra.query import SimpleStatement

QUERY = ("SELECT nickname, register_time FROM search_demo.users "
         "WHERE nickname LIKE '%将军%' ORDER BY register_time DESC LIMIT {}")


def run(session, limit, fetch_size):
    print(f"LIMIT {limit}, fetch_size {fetch_size}:")
    result = session.execute(SimpleStatement(QUERY.format(limit), fetch_size=fetch_size))
    pages, rows = 0, []
    while True:
        pages += 1
        names = [row.nickname for row in result.current_rows]
        rows += names
        print(f"  page {pages}: {names}  more={result.has_more_pages}")
        if not result.has_more_pages:
            break
        result.fetch_next_page()
    print(f"  -> {pages} pages, {len(rows)} rows, duplicates={len(rows) != len(set(rows))}")
    return rows


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    session = Cluster([host]).connect()

    paged = run(session, 20, 2)
    capped = run(session, 3, 2)
    unpaged = run(session, 20, 5000)

    # Paging must not change the answer, and the LIMIT bounds the query rather than the page.
    print()
    print("paged == unpaged:", paged == unpaged)
    print("limit honoured:", capped == unpaged[:3])


if __name__ == "__main__":
    main()
