#!/bin/bash
# mackor를 종료(키 매핑 복구)하고, 앱·설정·접근성 권한 항목을 지운다.
set -euo pipefail

osascript -e 'tell application id "io.mackor.app" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/mackor.app
defaults delete io.mackor.app 2>/dev/null || true
tccutil reset Accessibility io.mackor.app >/dev/null 2>&1 || true
echo "삭제했습니다."
