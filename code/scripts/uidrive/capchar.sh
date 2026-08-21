#!/bin/zsh
# Capture one character window — not the chat panel — at its live bounds.
#
# Usage: ./capchar.sh <pid> <out.png> [nth]     nth defaults to 1
#
# cap.sh takes the first window wider than 200pt, which is the panel. The
# characters are the narrow ones, and there is one per profile on the desktop,
# so this takes the other side of that same test plus an index. Same rule as
# cap.sh about never typing a rectangle: the bounds are read every time.
set -e
cd "$(dirname "$0")"
PID=$1
OUT=$2
N=${3:-1}
if [[ -z "$PID" || -z "$OUT" ]]; then
    echo "usage: capchar.sh <pid> <out.png> [nth]" >&2
    exit 64
fi
# A window on a display left of or above the main one has negative x or y —
# without the `-?` the line simply doesn't match and the script reports "is the
# panel open?" about a panel that is open, which cost a session's confidence in
# the tooling on 2026-08-21. Do not drop the `-?` when tidying this regex.
r=$(swift win.swift "$PID" \
    | sed -E 's/.* x=(-?[0-9.]+) y=(-?[0-9.]+) w=([0-9.]+) h=([0-9.]+).*/\1 \2 \3 \4/' \
    | awk -v n="$N" '$3+0<200 { c++; if (c==n) { print $1","$2","$3","$4; exit } }')
if [[ -z "$r" ]]; then
    echo "no character window #$N for pid $PID" >&2
    exit 1
fi
echo "character $r"
screencapture -x -R"$r" "$OUT"
