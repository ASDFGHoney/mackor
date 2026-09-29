#!/bin/bash
# build/mackor.app 을 만든다.
#   MACKOR_SIGN_IDENTITY  서명 인증서(기본: ad-hoc "-"). 배포용은 "Developer ID Application: 이름 (팀ID)"
#   MACKOR_ARCHS          기본 "arm64 x86_64"(유니버설). 개발 중엔 "arm64"만으로 빠르게.
#   MACKOR_VERSION        CFBundleShortVersionString 덮어쓰기(릴리스용)
set -euo pipefail
cd "$(dirname "$0")/.."

identity=${MACKOR_SIGN_IDENTITY:--}
archs=${MACKOR_ARCHS:-arm64 x86_64}
app=build/mackor.app

arch_flags=()
for arch in $archs; do arch_flags+=(--arch "$arch"); done
swift build -c release "${arch_flags[@]}"
binary=$(swift build -c release "${arch_flags[@]}" --show-bin-path)/mackor

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/mackor"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -n "${MACKOR_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MACKOR_VERSION" "$app/Contents/Info.plist"
fi

# 접근성 권한은 서명 신원에 묶인다. ad-hoc 서명은 빌드할 때마다 신원이 바뀌어 권한을 다시 받아야 한다.
sign_args=(--force --sign "$identity" --options runtime)
if [[ "$identity" == "-" ]]; then sign_args+=(--timestamp=none); else sign_args+=(--timestamp); fi
codesign "${sign_args[@]}" "$app"
codesign --verify --strict "$app"
echo "빌드 완료: $app ($(lipo -archs "$app/Contents/MacOS/mackor"), 서명: $identity)"
