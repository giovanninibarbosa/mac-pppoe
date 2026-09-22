#!/bin/bash
set -euo pipefail
APP="$(find ~/Library/Developer/Xcode/DerivedData build -name PPPoEClient.app -path '*Release*' -newermt '-1 hour' 2>/dev/null | head -1)"
[ -n "$APP" ] || { echo "FAIL: app not found in DerivedData"; exit 1; }
echo "APP: $APP"
echo "== archs =="
lipo -archs "$APP/Contents/MacOS/PPPoEClient"
lipo -archs "$APP/Contents/MacOS/PPPoEClient" | grep -q arm64 || { echo "FAIL: no arm64"; exit 1; }
echo "== deps =="
otool -L "$APP/Contents/MacOS/PPPoEClient" | head -10
echo "== codesign =="
codesign -dv "$APP" 2>&1 | head -3
echo "== launch smoke (5s) =="
"$APP/Contents/MacOS/PPPoEClient" & APP_PID=$!
sleep 5
if kill -0 $APP_PID 2>/dev/null; then
  kill $APP_PID
  wait $APP_PID 2>/dev/null || true
  rc=124
else
  rc=0
  wait $APP_PID 2>/dev/null || rc=$?
fi
# app runs until quit; timeout kill 124 acceptable
if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 143 ]; then
  echo "FAIL: launch rc=$rc"
  exit 1
fi
echo "PASS"
