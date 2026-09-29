#!/bin/bash
# 실제 애플 한국어 입력기를 대상으로 mackor를 종단 간 검증한다.
#
# - 이 터미널 앱에 접근성 권한이 있어야 한다(키 이벤트를 보내고, mackor 이벤트 탭을 띄우기 위해).
# - 실험 창이 맨 앞에 뜨고 자동으로 키가 입력된다. 실행 중엔 키보드·마우스를 건드리지 말 것.
#   실험 창이 맨 앞이 아니면 즉시 멈춰서 다른 앱에는 입력하지 않는다.
# - mackor는 --no-remap 으로 띄워 실제 키보드 매핑은 건드리지 않는다(F18을 직접 보낸다).
# - 입력 소스에 "ABC"와 "한국어 두벌식"이 켜져 있고 "이전 입력 소스 선택" 단축키가 켜져 있어야 한다.
# - 설치본 mackor는 먼저 종료할 것(두 인스턴스가 함께 전환한다).
#
# 진단용 환경 변수:
#   E2E_ONLY=이름일부  그 사례만    E2E_REPEAT=N  사례마다 N번    MACKOR_E2E_DIAG=1  진단 사례(D0~D3, P1~P2)도
#   MACKOR_ARGS="인자…"  mackor에 더 넘길 인자    MACKOR_BIN=경로  다른 빌드(예: 수정 전 기준선)
#   E2E_TRACE=1  실험 창이 키·입력 컨텍스트 기록을 남기고 실패 회차 기록을 build/e2e/에 모은다
#   E2E_LOG=경로  mackor 로그와 한국어 입력기(KIM_Extension) 활성화 기록을 그 파일에 받는다
set -euo pipefail
cd "$(dirname "$0")/.."

E2E_ONLY=${E2E_ONLY:-}
E2E_REPEAT=${E2E_REPEAT:-1}
MACKOR_ARGS=${MACKOR_ARGS:-}
MACKOR_BIN=${MACKOR_BIN:-.build/debug/mackor}
E2E_TRACE=${E2E_TRACE:-}
E2E_LOG=${E2E_LOG:-}

export MACKOR_E2E_DIR=${TMPDIR:-/tmp}/mackor-e2e
mkdir -p "$MACKOR_E2E_DIR" build/e2e
lab=build/e2e/Lab.app
swift build
swiftc -O Tools/e2e/switch-lab.swift -o build/e2e/switch-lab
mkdir -p "$lab/Contents/MacOS"
cp build/e2e/switch-lab "$lab/Contents/MacOS/switch-lab"
cat > "$lab/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.mackor.switchlab</string>
<key>CFBundleName</key><string>mackor 검증</string>
<key>CFBundleExecutable</key><string>switch-lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$lab" 2>/dev/null

korean=com.apple.inputmethod.Korean.2SetKorean
run_case() { # 이름, 기대값, 단계
  [[ -n $E2E_ONLY && $1 != *"$E2E_ONLY"* ]] && return 0
  local round started output
  for ((round = 1; round <= E2E_REPEAT; round++)); do
    build/e2e/switch-lab "sel:$korean" >/dev/null 2>&1
    sleep 0.3
    rm -f "$MACKOR_E2E_DIR/state.txt" "$MACKOR_E2E_DIR/trace.txt"
    open -n "$lab" --args --window ${E2E_TRACE:+--trace}
    sleep 0.5
    started=$(date +%H:%M:%S)
    output=$(build/e2e/switch-lab "ready $3 settle txt" 2>/dev/null | grep '^txt:' | sed -E 's/^txt: "(.*)" marked=.*/\1/')
    pkill -f "e2e/Lab.app/Contents/MacOS/switch-lab" 2>/dev/null || true
    sleep 0.3
    if [[ "$output" == "$2" ]]; then
      echo "[$started] ✔ $1 ($round)"
    else
      echo "[$started] ✘ $1 ($round) — 기대 \"$2\", 실제 \"$output\""
      failures=$((failures + 1))
      # set -e 아래라서 if로 쓴다(trace가 없거나 복사에 실패해도 나머지 사례를 계속 돈다). 사례 이름의 '/'도 '_'로 바꾼다.
      if [[ -f $MACKOR_E2E_DIR/trace.txt ]]; then
        cp "$MACKOR_E2E_DIR/trace.txt" "build/e2e/trace-${1//[\/ ]/_}-$round.txt" || true
      fi
    fi
  done
}

log_pid=
if [[ -n $E2E_LOG ]]; then
  /usr/bin/log stream --level debug --style compact \
    --predicate 'subsystem == "io.mackor.app" OR process == "KIM_Extension"' >"$E2E_LOG" 2>&1 &
  log_pid=$!
fi
# shellcheck disable=SC2086
"$MACKOR_BIN" --no-remap $MACKOR_ARGS >/dev/null 2>&1 &
mackor_pid=$!
trap 'kill $mackor_pid $log_pid 2>/dev/null || true' EXIT
sleep 1.5

failures=0
rep() { local n=$1; shift; for ((i = 0; i < n; i++)); do printf '%s ' "$*"; done; }
spaced() { # 간격(ms), 글자들: t:h wN t:e wN …
  local gap=$1 text=$2 out="" i
  for ((i = 0; i < ${#text}; i++)); do out+="t:${text:i:1} "; ((i < ${#text} - 1)) && out+="w$gap "; done
  printf '%s' "$out"
}
ga10=$(printf 'ㄱa%.0s' $(seq 10))

run_case "몰아치기(0ms)" "한dud한" "t:gks f79 t:dud f79 t:gks"
run_case "문장 사이 전환(0ms)" "안녕하세요hello반갑습니다" "t:dkssudgktpdy f79 t:hello f79 t:qksrkqtmqslek"
run_case "전환 20번 연타" "$ga10" "$(rep 10 't:r f79 t:a f79')"
run_case "사람 속도(40ms)" "한dud한" "t:g w40 t:k w40 t:s w40 f79 w40 t:d w40 t:u w40 t:d w40 f79 w40 t:g w40 t:k w40 t:s"
run_case "한/영 키를 누른 채 다음 단어" "프로그램code주가" "t:vmfhrmfoa F79 t:c U79 t:ode f79 t:wnrk"
run_case "조합 중 전환" "하k" "t:gk f79 t:k"
# 순서 경쟁: 전환이 끝나는 순간 날아오던 키가 보류분을 앞지르면 안녕lhelo, helloㅏㅎㄴ글 모양으로 틀린다.
run_case "20ms 간격 한→영→한(재현 시퀀스)" "안녕hello한글" "t:dkssud w20 f79 $(spaced 20 hello) w20 f79 $(spaced 20 gksrmf)"
run_case "10ms 간격 한→영→한" "안녕hello한글" "t:dkssud w10 f79 $(spaced 10 hello) w10 f79 $(spaced 10 gksrmf)"
run_case "20ms 간격 한→영 긴 단어" "안녕helloworld" "t:dkssud w20 f79 $(spaced 20 helloworld)"
run_case "20ms 간격 영→한 긴 단어" "hello한글입력" "f79 w400 t:hello w20 f79 $(spaced 20 gksrmfdlqfur)"
run_case "10ms 간격 영→한 긴 단어" "hello한글입력" "f79 w400 t:hello w10 f79 $(spaced 10 gksrmfdlqfur)"
run_case "누름이 겹치는 입력(10ms)" "안녕hello" "t:dkssud w20 f79 d4 w10 d14 w10 u4 w10 d37 w10 u14 w10 u37 w10 d37 w10 d31 w10 u37 w10 u31"
run_case "대문자 섞기(0ms)" "한Hello" "t:gks f79 t:Hello"
run_case "즉시 두 번 탭(0ms)" "한한" "t:gks f79 f79 t:gks"
run_case "세 번 탭(20ms)" "한dud" "t:gks w40 f79 w20 f79 w20 f79 w40 t:dud"
run_case "연달아 전환 사이 입력(10ms)" "한d한" "t:gks w40 f79 w10 t:d w10 f79 w10 t:g w10 t:k w10 t:s"
run_case "20ms 간격 전환 20번" "$ga10" "$(rep 10 't:r w20 f79 w20 t:a w20 f79 w20')"

if [[ -n ${MACKOR_E2E_DIAG:-} ]]; then
  # "전환 20번 연타" 간헐 실패 가르기. 끝의 t:k(ㅏ)는 전환 횟수 홀짝 확인.
  run_case "D0 연쇄+조합" "${ga10}ㅏ" "$(rep 10 't:r f79 t:a f79') w300 t:k"
  run_case "D1 연쇄, 조합 먼저 확정" "$(printf 'ㄱ a%.0s' $(seq 10))ㅏ" "$(rep 10 't:r_ f79 t:a f79') w300 t:k"
  run_case "D2 조합, 연쇄 없음" "${ga10}ㅏ" "t:r f79 t:a w200 $(rep 9 'f79 t:r w200 f79 t:a w200') f79 w300 t:k"
  run_case "D3 보류 없음(macOS만)" "${ga10}ㅏ" "$(rep 10 't:r w200 f79 w200 t:a w200 f79 w200') t:k"
  run_case "P1 전환 키만 20번 연타" "ㄱ" "$(rep 20 f79) t:r w4000"
  run_case "P2 전환 키만 20번(200ms)" "ㄱ" "$(rep 20 'f79 w200') t:r"
fi

echo
if [[ $failures == 0 ]]; then echo "모두 통과"; else echo "실패 ${failures}건"; exit 1; fi
