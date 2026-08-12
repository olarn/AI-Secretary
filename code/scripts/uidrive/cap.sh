#!/bin/zsh
# Capture the chat panel of a running AISecretary, at the bounds the window
# actually has right now.
#
# Usage: ./cap.sh <pid> <out.png>
#
# The reason this exists rather than a plain `screencapture -R`: a fixed
# rectangle typed from a previous run reads as "it fits" when it doesn't. A
# 720pt capture of a 643pt-tall window once hid an overflowing panel — the
# content below the crop simply wasn't in the picture. Ask the window.
#
# The first window wider than 200pt is the panel; the character window and the
# status item are narrower.
set -e
cd "$(dirname "$0")"
PID=$1
OUT=$2
if [[ -z "$PID" || -z "$OUT" ]]; then
    echo "usage: cap.sh <pid> <out.png>" >&2
    exit 64
fi
r=$(swift win.swift "$PID" \
    | sed -E 's/.* x=([0-9.]+) y=([0-9.]+) w=([0-9.]+) h=([0-9.]+).*/\1 \2 \3 \4/' \
    | awk '$3+0>200 {print $1","$2","$3","$4; exit}')
if [[ -z "$r" ]]; then
    echo "no window wider than 200pt for pid $PID — is the panel open?" >&2
    exit 1
fi
echo "panel $r"
screencapture -x -R"$r" "$OUT"
