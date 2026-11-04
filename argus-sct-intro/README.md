# Argus and SCT intro

Team presentation: how to use Argus and SCT to run tests, and the concepts behind them.

## Layout

- `deck.json` — slide order, sections, fonts
- `slides/<id>.html` — one slide per file: a single `<section>` on a 1920×1080 canvas, inline styles,
  speaker notes in a trailing `<aside>`
- `assets/` — logo and fonts
- `viewer/` — stylesheet and script that render the slides in a browser
- `build.sh` — assembles `deck.html` and prints `deck.pdf`

## Build

```bash
./build.sh        # deck.html + deck.pdf (needs Chromium; set CHROME=... if not found)
./build.sh html   # deck.html only
```

Open `deck.html` in a browser to present: arrow keys navigate, `n` toggles speaker notes, `p` prints.

## Editing

Edit the slide files directly, or change `deck.json` to reorder. The same files are the source of the
claude.ai artifact version, so either can be updated from the other.
