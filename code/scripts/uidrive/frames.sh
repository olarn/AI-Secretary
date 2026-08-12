#!/bin/zsh
# Three frames of the choice list: before any key, after Down, after Up.
# Only runs while the app is frontmost — synthetic keys have leaked before.
set -e
cd "$(dirname "$0")"
PID=$1
swift shot.swift "$PID" frame1.png 700
swift keysafe.swift "$PID" 125 1
sleep 0.6
swift shot.swift "$PID" frame2.png 700
swift keysafe.swift "$PID" 126 1
sleep 0.6
swift shot.swift "$PID" frame3.png 700
echo "captured frame1/2/3"
