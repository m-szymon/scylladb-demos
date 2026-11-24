#!/usr/bin/env python3
"""Draws the figures of the design pages as SVG files, next to this script.

Run it again after changing a figure:  python3 make_figures.py
The figures are drawings of the mechanisms, not plots of measurements.
"""

import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = 'font-family="system-ui, -apple-system, Segoe UI, Helvetica, Arial, sans-serif"'
INK, MUTED, LINE, BG, CARD = "#1f2933", "#52606d", "#9aa5b1", "#f8f9fb", "#ffffff"
BLUE, ORANGE, GREEN, PURPLE, RED = "#2f6fde", "#e07a1f", "#2a9d6f", "#b0429c", "#c0392b"
SOFT_BLUE, SOFT_GREEN, SOFT_ORANGE, GREY = "#dbe7fb", "#d8f0e5", "#fbe6d0", "#d5dae0"
SHARDS = [BLUE, ORANGE, GREEN, PURPLE]


def text(x, y, s, size=13, fill=INK, weight=None, anchor=None):
    extra = (f' font-weight="{weight}"' if weight else "") + (f' text-anchor="{anchor}"' if anchor else "")
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}"{extra}>{s}</text>'


def rect(x, y, w, h, fill=CARD, stroke=LINE, rx=6, sw=1.5):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'


def line(x1, y1, x2, y2, stroke=INK, sw=1.6, arrow=False, dash=None):
    extra = (' marker-end="url(#a)"' if arrow else "") + (f' stroke-dasharray="{dash}"' if dash else "")
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}"{extra}/>'


def save(name, width, height, label, body):
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" {FONT} role="img" aria-label="{label}">\n'
        f'<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{INK}"/></marker></defs>\n'
        f'<rect width="{width}" height="{height}" rx="10" fill="{BG}"/>\n' + "\n".join(body) + "\n</svg>\n"
    )
    with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
        f.write(svg)


def box(x, y, w, h, title, lines, fill=CARD, stroke=LINE):
    out = [rect(x, y, w, h, fill, stroke, rx=8), text(x + 14, y + 25, title, 15, weight=600)]
    yy = y + 48
    for item in lines:
        if isinstance(item, tuple):
            out.append(text(x + 14, yy, item[0], 13, weight=600))
            out.append(text(x + 32, yy, item[1], 13, MUTED))
        elif item:
            out.append(text(x + 32 if item.startswith(" ") else x + 14, yy, item.strip(), 13, MUTED))
        yy += 19
    return out


def labelled_arrow(x1, y1, x2, y2, n, label, lx, ly, anchor="middle"):
    return [
        line(x1, y1, x2, y2, arrow=True),
        f'<text x="{lx}" y="{ly}" text-anchor="{anchor}" font-size="12.5" fill="{INK}">'
        f'<tspan font-weight="700">{n}</tspan>  {label}</text>',
    ]


def path_of_a_query():
    b = []
    b += box(20, 60, 170, 110, "Client", ["SELECT ... WHERE", "name LIKE &#39;%ali%&#39;", "LIMIT 20"])
    b += box(300, 40, 230, 150, "ScyllaDB, the coordinator",
             ["picks the index whose order", "fits the query; asks the index", "node for a page of keys;", "tops a short page up"])
    b += box(300, 270, 230, 104, "ScyllaDB, the replicas", ["hold the rows: read by key,", "wherever on the ring they are"])
    b += box(712, 40, 248, 334, "Index node (vector-store)",
             [("1", "split the pattern into grams"), " &#39;ali&#39;", ("2", "walk the segments in the"),
              " index&#39;s order, skipping", " what cannot match", ("3", "check each candidate"),
              " against the stored value", ("4", "stop at 20 rows, or when"), " the request&#39;s budget of",
              " time ends", "", "answers 20 keys in order,", "and a cursor for the next page"],
             fill="#eef4ff", stroke=BLUE)
    b += labelled_arrow(190, 95, 298, 95, "1", "query", 244, 86)
    b += labelled_arrow(530, 85, 710, 85, "2", "pattern, limit, cursor", 620, 76)
    b += labelled_arrow(710, 150, 532, 150, "3", "keys, next cursor", 620, 141)
    b += labelled_arrow(415, 190, 415, 268, "4", "read the rows", 426, 234, "start")
    b += labelled_arrow(298, 140, 192, 140, "5", "page", 244, 131)
    save("path-of-a-query.svg", 980, 400, "The path of a LIKE query through ScyllaDB and the index node", b)


NAMES = ["malina", "alina", "linali", "natalia", "kalina", "olaf"]


def grams():
    b = [text(400, 32, "LIKE &#39;%alin%&#39; on six names, with pieces of three characters", 15, anchor="middle")]
    # the values
    b.append(text(40, 70, "The values", 14, weight=600))
    for i, name in enumerate(NAMES):
        y = 96 + i * 26
        b.append(text(40, y, str(i + 1), 13, MUTED))
        b.append(text(62, y, name, 14))
    # the index
    b.append(text(210, 70, "The index: piece &#8594; rows that hold it", 14, weight=600))
    entries = [("ali", [1, 2, 3, 4, 5], BLUE), ("lin", [1, 2, 3, 5], ORANGE), ("ola", [6], GREY), ("...", [], GREY)]
    for i, (gram, rows, colour) in enumerate(entries):
        y = 84 + i * 40
        b.append(rect(210, y, 58, 28, SOFT_BLUE if colour == BLUE else SOFT_ORANGE if colour == ORANGE else "#eceff3",
                      colour, rx=5))
        b.append(text(239, y + 19, gram, 14, weight=600, anchor="middle"))
        for j, row in enumerate(rows):
            b.append(f'<circle cx="{298 + j * 30}" cy="{y + 14}" r="11" fill="{CARD}" stroke="{colour}" stroke-width="1.5"/>')
            b.append(text(298 + j * 30, y + 19, str(row), 13, anchor="middle"))
    # the query
    x = 500
    b.append(text(x, 70, "The query", 14, weight=600))
    b.append(text(x, 96, "1  &#39;alin&#39; is longer than a piece, so it is cut:", 13, MUTED))
    b.append(text(x + 18, 116, "every match must hold &#39;ali&#39; and &#39;lin&#39;", 13, MUTED))
    b.append(text(x, 146, "2  rows in both lists: the candidates", 13, MUTED))
    for j, row in enumerate([1, 2, 3, 5]):
        b.append(f'<circle cx="{x + 30 + j * 34}" cy="170" r="12" fill="{SOFT_GREEN}" stroke="{GREEN}" stroke-width="1.5"/>')
        b.append(text(x + 30 + j * 34, 175, str(row), 13, anchor="middle"))
    b.append(text(x, 210, "3  check each stored value", 13, MUTED))
    checks = [("malina", True), ("alina", True), ("linali", False), ("kalina", True)]
    for i, (name, ok) in enumerate(checks):
        y = 236 + i * 24
        b.append(text(x + 18, y, name, 14))
        b.append(text(x + 100, y, "holds &#39;alin&#39;" if ok else "holds both pieces, apart", 13, GREEN if ok else RED))
        b.append(text(x + 268, y, "&#10003;" if ok else "&#10007;", 15, GREEN if ok else RED, weight=700))
    b.append(text(40, 290, "Row 6 is never looked at.", 13, MUTED))
    b.append(text(40, 312, "Row 3 is looked at and dropped:", 13, MUTED))
    b.append(text(40, 332, "the price of pieces shorter than the keyword.", 13, MUTED))
    save("grams.svg", 800, 350, "A pattern answered from the pieces of the values, then checked", b)


MATCH = [0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0]


def strip(b, x, y, cells, w=27, h=30, looked=None, taken=None):
    for i, m in enumerate(cells):
        fill = CARD
        if looked is not None and i < looked:
            fill = "#eceff3"
        if m and (taken is None or i in taken):
            fill = GREEN
        elif m:
            fill = SOFT_GREEN
        b.append(rect(x + i * w, y, w - 3, h, fill, LINE if not m else GREEN, rx=4, sw=1.2))


def order():
    b = [text(400, 32, "The first 3 matches, newest first. A green cell is a row that matches.", 15, anchor="middle")]
    x = 76
    b.append(text(x, 70, "Index kept in the query&#39;s order", 14, weight=600))
    strip(b, x, 82, MATCH, looked=8, taken={2, 5, 7})
    b.append(text(x, 132, "newest", 12, MUTED))
    b.append(text(x + 24 * 27 - 3, 132, "oldest", 12, MUTED, anchor="end"))
    b.append(line(x + 8 * 27 - 2, 76, x + 8 * 27 - 2, 118, RED, 2))
    b.append(text(x + 8 * 27 + 6, 132, "stop: the page is full after 8 rows", 13, RED))
    shuffled = MATCH[:]
    random.Random(3).shuffle(shuffled)
    b.append(text(x, 186, "Index in no order", 14, weight=600))
    strip(b, x, 198, shuffled, looked=24, taken=set())
    b.append(text(x, 250, "every row has to be looked at: 8 matches found, sorted, 3 kept", 13, RED))
    b.append(text(400, 292, "With ten million rows the first costs the same 8 rows. The second costs ten million.", 13, MUTED, anchor="middle"))
    save("order.svg", 800, 312, "A page read from an index in the query's order, against one in no order", b)


def cursor():
    b = [text(400, 32, "Two pages of 3. The cursor is a place in the order, not a count of rows.", 15, anchor="middle")]
    x, y = 76, 84
    strip(b, x, y, MATCH, taken={2, 5, 7, 11, 13, 16})
    # pages
    def bracket(i0, i1, label, colour):
        x0, x1 = x + i0 * 27 - 2, x + (i1 + 1) * 27 - 2
        b.append(f'<path d="M{x0},{y - 6} v-10 H{x1} v10" fill="none" stroke="{colour}" stroke-width="2"/>')
        b.append(text((x0 + x1) / 2, y - 22, label, 13, colour, weight=600, anchor="middle"))
    bracket(0, 7, "page 1", BLUE)
    bracket(8, 16, "page 2", PURPLE)
    cx = x + 8 * 27 - 2
    b.append(line(cx, y + 62, cx, y + 36, arrow=True))
    b.append(text(cx, y + 80, "cursor: the sort value and the key of the last row of page 1", 13, anchor="middle"))
    b.append(text(x, y + 124, "A row deleted or added before the cursor moves nothing: page 2 still starts right after that row.", 13, MUTED))
    b.append(text(x, y + 146, "A page number or an offset would shift, and skip a row or show one twice.", 13, MUTED))
    save("cursor.svg", 800, 250, "Two pages joined by a cursor", b)


def pieces():
    b = [text(400, 32, "The index is a set of pieces (segments). Each bar is one, drawn over the part of the order it holds.", 14, anchor="middle")]
    def panel(x, title, bars, note, colour):
        b.append(text(x, 66, title, 14, weight=600))
        for i, (a, c) in enumerate(bars):
            b.append(rect(x + a, 80 + i * 22, c, 15, colour[i] if isinstance(colour, list) else colour, "none", rx=4, sw=0))
        b.append(line(x, 200, x + 330, 200, MUTED, 1.2, arrow=True))
        b.append(text(x, 218, "newest", 12, MUTED))
        b.append(text(x + 330, 218, "oldest", 12, MUTED, anchor="end"))
        # the page
        b.append(rect(x, 74, 26, 122, "none", RED, rx=4, sw=2))
        b.append(text(x + 34, 240, note, 13, RED))
    panel(40, "As rows arrive: every piece spans everything",
          [(0, 330), (4, 322), (0, 326), (8, 320), (2, 328)], "the page (red) crosses all 5 pieces", SOFT_ORANGE)
    panel(430, "Tidied: pieces side by side",
          [(0, 64), (66, 64), (132, 64), (198, 64), (264, 66)], "the page crosses 1 piece", SOFT_GREEN)
    b.append(line(378, 130, 422, 130, arrow=True))
    b.append(text(400, 120, "repair", 12, MUTED, anchor="middle"))
    b.append(text(400, 282, "Two kinds of pieces are kept apart: fresh ones, as commits leave them, and ordered ones, which never overlap.", 13, MUTED, anchor="middle"))
    b.append(text(400, 302, "A repair step moves fresh rows into the ordered kind, the worst stretch first, when the node has time.", 13, MUTED, anchor="middle"))
    save("pieces.svg", 800, 322, "Pieces of the index overlapping, and side by side after a repair", b)


def runs_figure(name, title, sorted_runs, caption):
    rnd = random.Random(11)
    b = [text(400, 32, title, 15, anchor="middle")]
    x0, y0, w, h = 80, 60, 640, 200
    b.append(rect(x0, y0, w, h, CARD, LINE, rx=4, sw=1.2))
    b.append(text(x0 - 10, y0 + 12, "high", 12, MUTED, anchor="end"))
    b.append(text(x0 - 10, y0 + h, "low", 12, MUTED, anchor="end"))
    b.append(f'<text x="{x0 - 44}" y="{y0 + h / 2}" font-size="12" fill="{MUTED}" text-anchor="middle" transform="rotate(-90 {x0 - 44} {y0 + h / 2})">place in the order</text>')
    b.append(text(x0 + w / 2, y0 + h + 22, "position inside the piece, as the rows were written", 12, MUTED, anchor="middle"))
    floor = y0 + 44
    if sorted_runs:
        n = 4
        for r in range(n):
            xa, xb = x0 + 8 + r * w / n, x0 + (r + 1) * w / n - 8
            ya, yb = y0 + h - 8, y0 + 8
            # the part under the floor: thin; over it: thick
            t = (ya - floor) / (ya - yb)
            xm = xa + (xb - xa) * t
            b.append(line(xa, ya, xm, floor, LINE, 2))
            b.append(line(xm, floor, xb, yb, GREEN, 5))
        b.append(line(x0, floor, x0 + w, floor, RED, 1.5, dash="6 4"))
        b.append(text(x0 + w + 8, floor + 4, "the page", 12, RED))
        b.append(text(x0 + w + 8, floor + 20, "ends here", 12, RED))
    else:
        for _ in range(170):
            px, py = x0 + 8 + rnd.random() * (w - 16), y0 + 8 + rnd.random() * (h - 16)
            b.append(f'<circle cx="{px:.0f}" cy="{py:.0f}" r="2.6" fill="{GREEN if py < floor else LINE}"/>')
        b.append(line(x0, floor, x0 + w, floor, RED, 1.5, dash="6 4"))
        b.append(text(x0 + w + 8, floor + 4, "the page", 12, RED))
        b.append(text(x0 + w + 8, floor + 20, "ends here", 12, RED))
    for i, c in enumerate(caption):
        b.append(text(400, y0 + h + 52 + i * 20, c, 13, MUTED, anchor="middle"))
    save(name, 800, y0 + h + 52 + len(caption) * 20, title, b)


def walk():
    runs_figure("walk.svg", "One piece of four sorted runs. Green is what a page reads.", True,
                ["Each run is read from its high end down to the line where the page is full.",
                 "Everything under the line is never read, however large the piece is."])


def commits():
    b = [text(400, 32, "The same commit of rows, written two ways. Green is what a page has to read.", 15, anchor="middle")]
    rnd = random.Random(5)
    def panel(x, title, sorted_runs):
        w, h, y0 = 320, 170, 78
        b.append(text(x, 66, title, 14, weight=600))
        b.append(rect(x, y0, w, h, CARD, LINE, rx=4, sw=1.2))
        floor = y0 + 40
        if sorted_runs:
            for r in range(4):
                xa, xb = x + 6 + r * w / 4, x + (r + 1) * w / 4 - 6
                ya, yb = y0 + h - 8, y0 + 8
                t = (ya - floor) / (ya - yb)
                xm = xa + (xb - xa) * t
                b.append(line(xa, ya, xm, floor, LINE, 2))
                b.append(line(xm, floor, xb, yb, GREEN, 5))
        else:
            for _ in range(120):
                px, py = x + 8 + rnd.random() * (w - 16), y0 + 8 + rnd.random() * (h - 16)
                b.append(f'<circle cx="{px:.0f}" cy="{py:.0f}" r="2.6" fill="{GREEN}"/>')
        b.append(line(x, floor, x + w, floor, RED, 1.5, dash="6 4"))
    panel(60, "In the order they arrived", False)
    panel(420, "Sorted by key, in four groups", True)
    b.append(text(220, 270, "nothing tells where the high rows are:", 13, MUTED, anchor="middle"))
    b.append(text(220, 290, "the whole piece is read", 13, RED, anchor="middle"))
    b.append(text(580, 270, "the high rows are at the end of each run:", 13, MUTED, anchor="middle"))
    b.append(text(580, 290, "only those are read", 13, GREEN, anchor="middle"))
    save("commits.svg", 800, 312, "A commit written as it came, and written in key order", b)


def budget():
    b = [text(400, 32, "A page of 20 that is expensive to fill: three requests of at most 50 ms each.", 15, anchor="middle")]
    x0, y = 60, 86
    b.append(text(x0, y - 16, "Index node", 14, weight=600))
    reqs = [("7 rows", 0), ("no rows", 1), ("13 rows", 2)]
    for label, i in reqs:
        x = x0 + i * 230
        wdt = 200 if i < 2 else 130
        b.append(rect(x, y, wdt, 34, SOFT_BLUE, BLUE, rx=5))
        b.append(text(x + wdt / 2, y + 22, f"request {i + 1}: {label}", 13, anchor="middle"))
        if i < 2:
            b.append(line(x + wdt, y - 6, x + wdt, y + 40, RED, 2))
            b.append(text(x + wdt, y + 56, "50 ms: stop,", 12, RED, anchor="middle"))
            b.append(text(x + wdt, y + 72, "return a cursor", 12, RED, anchor="middle"))
            b.append(line(x + wdt + 4, y + 17, x + 228, y + 17, arrow=True))
    b.append(text(x0, y + 122, "ScyllaDB", 14, weight=600))
    b.append(rect(x0, y + 134, 590, 34, SOFT_GREEN, GREEN, rx=5))
    b.append(text(x0 + 295, y + 156, "follows the cursor until the page has its 20 rows, then answers the client", 13, anchor="middle"))
    b.append(text(x0, y + 204, "No request holds a thread of the index node for more than about 50 ms.", 13, MUTED))
    b.append(text(x0, y + 224, "A paged query that is not full after half of its timeout is handed over as it is, with more to come.", 13, MUTED))
    save("budget.svg", 800, 330, "An expensive page served by several short requests", b)


def page_on_the_ring():
    def ring(cx, cy, r, dots, title, sub):
        out, n, counts = [], 16, [0] * 4
        for t in range(n):
            a0 = -math.pi / 2 + 2 * math.pi * t / n + 0.012
            a1 = -math.pi / 2 + 2 * math.pi * (t + 1) / n - 0.012
            out.append(
                f'<path d="M{cx + r * math.cos(a0):.1f},{cy + r * math.sin(a0):.1f} A{r},{r} 0 0 1 '
                f'{cx + r * math.cos(a1):.1f},{cy + r * math.sin(a1):.1f}" stroke="{SHARDS[t % 4]}" stroke-width="16" fill="none"/>'
            )
        for f in dots:
            a = -math.pi / 2 + 2 * math.pi * f
            counts[int(f * n) % 4] += 1
            out.append(f'<circle cx="{cx + (r - 24) * math.cos(a):.1f}" cy="{cy + (r - 24) * math.sin(a):.1f}" r="4.5" fill="{INK}"/>')
        out.append(text(cx, cy - 6, title, 17, weight=600, anchor="middle"))
        out.append(text(cx, cy + 16, sub, 13, MUTED, anchor="middle"))
        out.append(line(cx, cy - r - 14, cx, cy - r + 12, INK, 2))
        out.append(text(cx, cy - r - 20, "lowest token", 12, MUTED, anchor="middle"))
        y = cy + r + 44
        out.append(text(cx - 150, y, "rows read per shard:", 13, MUTED))
        for s in range(4):
            x = cx - 10 + s * 52
            out.append(rect(x, y - 13, 14, 14, SHARDS[s], "none", rx=3, sw=0))
            out.append(text(x + 20, y, str(counts[s]), 14, weight=600))
        return out
    rnd = random.Random(7)
    b = [text(400, 34, "The 20 rows of one first page, on the token ring. Each arc is a tablet; its colour is the shard that owns it.", 15, anchor="middle")]
    b += ring(210, 215, 130, [0.0025 + 0.0028 * i for i in range(20)], "token order", "as a scan returns it")
    b += ring(590, 215, 130, sorted(rnd.random() for _ in range(20)), "scattered", "the default")
    b.append(text(400, 424, "A drawing, not a measurement: 16 tablets on 4 shards. The run had 64 tablets, and the first one held more than a page of matches.", 12, MUTED, anchor="middle"))
    save("page-on-the-ring.svg", 800, 440, "The rows of a first page on the token ring, in token order and scattered", b)


def classes():
    b = [text(400, 32, "Four threads of the index node, three kinds of work waiting for them.", 15, anchor="middle")]
    queues = [
        ("Searches", SOFT_BLUE, BLUE, 5, ["never less than a quarter", "of the threads&#39; time"]),
        ("Live writes", SOFT_GREEN, GREEN, 3, ["first: a new row must not", "wait behind the searches"]),
        ("Rows of a build", SOFT_ORANGE, ORANGE, 6, ["only when nothing else waits,", "or under a tenth of the time;", "on 2 threads at most"]),
    ]
    for i, (name, soft, colour, n, notes) in enumerate(queues):
        y = 70 + i * 96
        b.append(text(40, y + 4, name, 14, weight=600))
        for j in range(n):
            b.append(rect(40 + j * 26, y + 16, 22, 26, soft, colour, rx=4, sw=1.3))
        for k, note in enumerate(notes):
            b.append(text(230, y + 22 + k * 18, note, 13, MUTED))
        b.append(line(450, y + 29, 556, 196 + (i - 1) * 20, MUTED, 1.4, arrow=True))
    for w in range(4):
        y = 106 + w * 46
        colour, soft = (ORANGE, SOFT_ORANGE) if w == 3 else (BLUE, SOFT_BLUE) if w < 2 else (GREEN, SOFT_GREEN)
        b.append(rect(566, y, 180, 36, soft, colour, rx=6))
        b.append(text(656, y + 23, f"thread {w + 1}", 13, anchor="middle"))
    b.append(text(656, 92, "the pool", 14, weight=600, anchor="middle"))
    b.append(text(400, 352, "A thread that comes free takes its next task by these rules. A task is never interrupted, so tasks have to be short.", 13, MUTED, anchor="middle"))
    save("classes.svg", 800, 372, "Three classes of work sharing the index node's threads", b)


if __name__ == "__main__":
    for figure in (path_of_a_query, grams, order, cursor, pieces, walk, commits, budget, page_on_the_ring, classes):
        figure()
