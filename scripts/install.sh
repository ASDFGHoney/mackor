#!/bin/bash
# 로컬 빌드(build/mackor.app)를 /Applications 에 설치하고 실행한다. brew 설치와 같은 흐름을 재현한다.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d build/mackor.app ]] || { echo "먼저 scripts/build.sh 를 실행하세요." >&2; exit 1; }
# 정상 종료시켜 키 매핑을 되돌린 뒤 교체한다.
osascript -e 'tell application id "io.mackor.app" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/mackor.app
ditto build/mackor.app /Applications/mackor.app
open /Applications/mackor.app
echo "설치했습니다. 처음 한 번 접근성 권한을 허용하면 바로 동작합니다."
