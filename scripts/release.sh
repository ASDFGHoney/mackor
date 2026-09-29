#!/bin/bash
# 배포용 zip을 만든다: Developer ID 서명 → 공증 → 스테이플 → zip → sha256.
# brew 설치 시 macOS가 "확인되지 않은 개발자" 경고 없이 바로 실행하려면 공증이 필요하다.
#
#   MACKOR_VERSION         예: 0.1.0 (필수)
#   MACKOR_SIGN_IDENTITY   "Developer ID Application: 이름 (팀ID)" (필수)
#   MACKOR_NOTARY_PROFILE  xcrun notarytool store-credentials 로 저장한 프로필 이름 (필수)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${MACKOR_VERSION:?예: MACKOR_VERSION=0.1.0}"
: "${MACKOR_SIGN_IDENTITY:?Developer ID Application 인증서 이름}"
: "${MACKOR_NOTARY_PROFILE:?notarytool 키체인 프로필 이름}"
[[ "$MACKOR_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "버전 형식: X.Y.Z" >&2; exit 1; }

MACKOR_VERSION=$MACKOR_VERSION scripts/build.sh
swift test

zip=build/mackor-$MACKOR_VERSION.zip
ditto -c -k --keepParent --norsrc build/mackor.app "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$MACKOR_NOTARY_PROFILE" --wait
xcrun stapler staple build/mackor.app
rm "$zip"
ditto -c -k --keepParent --norsrc build/mackor.app "$zip"
spctl --assess --type execute --verbose build/mackor.app

sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
echo
echo "릴리스 파일: $zip"
echo "Casks/mackor.rb 에 반영: version \"$MACKOR_VERSION\" / sha256 \"$sha\""
