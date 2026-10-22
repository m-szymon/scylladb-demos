#!/bin/bash
# Presents a demo live: cqlsh in a tmux session of its own, with the statements of the demo's CQL
# file one key press away. Each demo directory has a present.sh that calls this with its own name,
# CQL file and cqlsh command.
#
#   PgDn  (or Alt-n)  types the next statement without running it; pressed again, runs it
#   PgUp  (or Alt-p)  types the previous statement again
#   Alt-r             types the current statement again, e.g. after editing it by hand
#   Enter             runs what is typed, as usual
#   Ctrl-D            leaves cqlsh, which ends the session
#
# Comments are not typed. EXPAND ON / EXPAND OFF lines are not stops of their own: the one in force
# for a statement is run just before it is typed, when it differs from cqlsh's current setting.
# The screen is cleared before each statement (PRESENT_CLEAR=0 keeps the previous output), except
# when PgDn follows a statement that prints no rows, such as a CREATE FUNCTION: that one stays on
# screen above the next, e.g. the query calling the function. The status line shows the section,
# from the file's "-- N. title" comments, and the position.
# The session runs on its own tmux server, without ~/.tmux.conf, so other sessions and their key
# bindings are untouched. The mouse wheel scrolls back through long output. Closing the terminal,
# or detaching with Ctrl-b d, leaves the session running: running this again reattaches to it, at
# the same statement. Leaving cqlsh ends it.
#
# -s presents only the given sections, by the numbers of their "-- N. title" comments: a list of
# numbers and ranges such as 0-7 or 1,3,5-6. A lettered section ("-- 6a. title") counts as its
# number.
#
# Usage: common/present.sh [-s sections] <demo> <cql-file> <cqlsh-command>...
set -euo pipefail

self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")

# Key binding mode: present.sh --key <tmux-socket> <state-dir> step|back|again|enter
if [ "${1:-}" = --key ]; then
    sock=$2 state=$3 action=$4
    exec 9>"$state/lock"
    flock 9
    t() { tmux -L "$sock" "$@"; }
    pane=demo:0.0
    # Types text literally. tmux takes an argument ending in ';' as a command separator and drops
    # the ';', unless it is escaped.
    type() {
        local text=$1
        [ "${text%;}" = "$text" ] || text="${text%;}\\;"
        t send-keys -t "$pane" -l -- "$text"
    }
    n=$(wc -l < "$state/index")
    pos=$(cat "$state/pos") typed=$(cat "$state/typed") expand=$(cat "$state/expand")

    # show <i> [forward]: types statement i; forward when PgDn moves on to it.
    show() {
        local i=$1 forward=${2:-} want section lines k prev
        IFS=$'\t' read -r want section < <(sed -n "${i}p" "$state/index")
        if [ "$want" != "$expand" ]; then
            type "EXPAND $want;"
            t send-keys -t "$pane" Enter
            echo "$want" > "$state/expand"
            sleep 0.5
        fi
        # Only a SELECT leaves output worth clearing; anything else stays above the next statement.
        prev=
        [ -z "$forward" ] || [ "$i" -le 1 ] || read -r prev _ < "$state/$(printf %03d $((i - 1))).cql"
        if [ "${PRESENT_CLEAR:-1}" = 1 ] && { [ -z "$forward" ] || [ "$i" -le 1 ] || [ "${prev^^}" = SELECT ]; }; then
            t send-keys -t "$pane" C-l
            sleep 0.1
        fi
        # Line by line, so that cqlsh takes each continuation line before the next one arrives.
        mapfile -t lines < "$state/$(printf %03d "$i").cql"
        for k in "${!lines[@]}"; do
            [ -z "${lines[k]}" ] || type "${lines[k]}"
            if [ "$k" -lt $((${#lines[@]} - 1)) ]; then
                t send-keys -t "$pane" Enter
                sleep 0.05
            fi
        done
        echo "$i" > "$state/pos"
        echo 1 > "$state/typed"
        [ "${#section}" -le 60 ] || section="${section:0:59}…"
        t set-option -t demo status-right "#[bold]${section}#[nobold]  $i/$n "
    }
    # Drops a typed statement that was not run, before typing another one.
    cancel() {
        if [ "$typed" = 1 ]; then
            t send-keys -t "$pane" C-c
            sleep 0.2
        fi
    }

    case $action in
        step)
            if [ "$typed" = 1 ]; then
                t send-keys -t "$pane" Enter
                echo 0 > "$state/typed"
            elif [ "$pos" -lt "$n" ]; then
                show $((pos + 1)) forward
            else
                t display-message "end of the demo"
            fi ;;
        back)
            cancel
            show $((pos > 1 ? pos - 1 : 1)) ;;
        again)
            cancel
            [ "$pos" -lt 1 ] || show "$pos" ;;
        enter)
            t send-keys -t "$pane" Enter
            echo 0 > "$state/typed" ;;
    esac
    exit 0
fi

usage="usage: $0 [-s sections] <demo> <cql-file> <cqlsh-command>..."
sections=
if [ "${1:-}" = -s ]; then
    sections=${2:?$usage}
    shift 2
fi
demo=${1:?$usage}
cql=${2:?$usage}
shift 2
[ $# -gt 0 ] || { echo "$usage" >&2; exit 1; }

sock=present-$demo
# Attaches, and once the session has ended (cqlsh left), removes its server and state directory.
attach() {
    TMUX= tmux -L "$sock" attach -t demo || true
    if ! tmux -L "$sock" has-session -t demo 2>/dev/null; then
        tmux -L "$sock" kill-server 2>/dev/null || true
        rm -rf "$1"
    fi
}
if tmux -L "$sock" has-session -t demo 2>/dev/null; then
    attach "$(tmux -L "$sock" show-environment -g PRESENT_STATE | sed 's/^PRESENT_STATE=//')"
    exit 0
fi

state=$(mktemp -d)

# One file per statement, NNN.cql, and one index line per statement: the EXPAND setting in force
# and the section title. A statement ends at a line ending in ';' outside a $$ ... $$ body.
# Statements of sections left out by -s are dropped; EXPAND lines are followed in all of them.
awk -v dir="$state" -v sections="$sections" '
    BEGIN {
        n = 0; expand = "OFF"; section = ""; in_stmt = 0; in_body = 0; keep = 1
        if (sections != "") {
            k = split(sections, parts, ",")
            for (i = 1; i <= k; i++) {
                if (split(parts[i], r, "-") == 2) for (j = r[1] + 0; j <= r[2] + 0; j++) wanted[j] = 1
                else wanted[parts[i] + 0] = 1
            }
        }
    }
    !in_stmt {
        if ($0 ~ /^[[:space:]]*$/) next
        if ($0 ~ /^[[:space:]]*--/) {
            if ($0 ~ /^-- [0-9]+[a-z]?\. /) {
                section = substr($0, 4)
                keep = sections == "" || ((section + 0) in wanted)
            }
            next
        }
        if (toupper($0) ~ /^[[:space:]]*EXPAND[[:space:]]+(ON|OFF)[[:space:]]*;[[:space:]]*$/) {
            expand = toupper($0) ~ /ON/ ? "ON" : "OFF"
            next
        }
        in_stmt = 1
        if (keep) file = sprintf("%s/%03d.cql", dir, ++n)
    }
    {
        if (keep) print > file
        line = $0
        if (gsub(/\$\$/, "", line) % 2) in_body = !in_body
        if (!in_body && $0 ~ /;[[:space:]]*$/) {
            if (keep) {
                close(file)
                printf "%s\t%s\n", expand, section > (dir "/index")
            }
            in_stmt = 0
        }
    }
' "$cql"
echo 0 > "$state/pos"
echo 0 > "$state/typed"
echo OFF > "$state/expand"

key() { echo "run-shell -b \"'$self' --key '$sock' '$state' $1\""; }
tmux -L "$sock" -f /dev/null new-session -d -s demo "$@"
tmux -L "$sock" set-environment -g PRESENT_STATE "$state"
tmux -L "$sock" source-file - <<EOF
set -g mouse on
set -g history-limit 50000
set -g escape-time 10
set -g status-style "bg=default,fg=colour244"
set -g status-left " $demo demo "
set -g status-left-length 40
set -g window-status-format ""
set -g window-status-current-format ""
set -g status-right "PgDn: first statement "
set -g status-right-length 120
bind -n PageDown $(key step)
bind -n M-n $(key step)
bind -n PageUp $(key back)
bind -n M-p $(key back)
bind -n M-r $(key again)
bind -n Enter $(key enter)
EOF
attach "$state"
