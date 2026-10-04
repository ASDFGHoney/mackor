# mackor

왼쪽 한/영 키(Caps Lock)를 빠릿빠릿하게. 누르는 순간 한/영이 바뀌고, 아무리 빠르게 쳐도 전환 직후 친 글자가 씹히지 않습니다.
애플 한국어 입력기와 시스템 설정은 그대로 둡니다. (Caps Lock은 한국어 자판에서 ‘한/A’라고 적힌 키입니다.)
DJI Mic Mini 수신기를 꽂으면 송신기 버튼으로 받아쓰기도 켜고 끌 수 있습니다([DJI 마이크 버튼](#dji-마이크-버튼)).

## 설치

macOS 13(Ventura) 이상, Apple 실리콘·인텔 맥에서 동작합니다.

```sh
brew install --cask ASDFGHoney/tap/mackor
```

Homebrew를 쓰지 않으면 [최신 릴리스](https://github.com/ASDFGHoney/mackor/releases/latest)에서 `mackor-버전.zip`을 받아
`mackor.app`을 응용 프로그램 폴더로 옮긴 뒤 실행하세요.

설치한 뒤 mackor를 한 번 실행하세요(`open -a mackor`). 로그인 항목에 등록되어 이후에는 로그인하면 자동으로 실행됩니다.
처음 뜨는 설정 도우미를 따라 **접근성 권한**을 한 번 허용하면 끝입니다.
(키 입력을 가로채는 앱은 macOS 보안상 이 한 번의 허용을 피할 수 없습니다.)
입력 소스 추가, 시스템 단축키 변경, 재시작은 필요 없습니다.

mackor가 켜져 있는 동안 Caps Lock은 대문자 고정 대신 한/영 전환에만 쓰입니다. 대문자는 Shift로 입력하고, mackor를 종료하면 Caps Lock이 원래대로 돌아옵니다.

## 왜 느리고 씹히는가

**1) macOS 기본 Caps Lock 전환은 늦고, 가끔 먹히지 않습니다.** 한국어 로캘에서 기본으로 켜져 있는
‘Caps Lock 키로 ABC 입력 소스 전환’(한국어 자판에서는 ‘한/A 키로 ABC 입력 소스 전환’)은 키를 **뗄 때** 전환합니다(길게 누르면 대문자 고정).
게다가 타이핑 직후(마지막 키 뒤 약 0.25초 안)에는 macOS가 Caps Lock에 75ms 지연 판정을 다시 켜서, 그보다 짧게 톡 친 Caps Lock은
**무시**되고 그보다 길게 누르면 약 75~85ms 늦게 들어갑니다. 개발자의 맥(macOS 27)에서 24시간 동안 모은 로그로는 Caps Lock 149번 중 93번이 약 80ms 늦게 전달됐습니다.
(근거: IOHIDKeyboardFilter의 `processCapsLockDelay`, HIToolbox TSM의 `CapsLockDelayOverride` 전환, 통합 로그)

**2) 입력 소스 전환 자체가 비동기입니다.** 전환 단축키가 처리된 뒤 실제로 앱의 입력기가 바뀌기까지
개발자의 맥(macOS 27)에서 측정한 값으로 **20~130ms**가 걸리고, 그 사이에 친 키는 이전 언어로 들어갑니다.

| 측정 | 결과 |
|---|---|
| ⌃Space 직후 0ms에 `hello` | `ㅗ디ㅣㅐ` |
| 전환 후 10ms에 입력 | 이전 언어 |
| 전환 후 30ms 이상 | 정상 |

**3) 기존 요령은 절반만 고칩니다.** Caps Lock을 F18로 바꾸는 요령(hidutil, Karabiner-Elements)은 1)을 없애지만 2)는 남습니다.
mackor는 둘 다 없앱니다. Caps Lock을 누르는 순간 전환을 시작하고, 전환이 끝날 때까지 뒤따르는 키를 붙잡아 두었다가 순서대로 내보냅니다.

## 어떻게 동작하나

```
Caps Lock ──(HID 리매핑, 공개 IOKit API)──▶ F18
                                             │ 이벤트 탭
                                             ▼
                        ⌃Space(시스템 기본 전환 단축키)를 즉시 합성
                                             │
           전환이 실제로 끝날 때까지 뒤따르는 키를 메모리에 보류
                                             │ 현재 입력 소스가 바뀐 것을 확인
                                             ▼
                   보류한 키를 이벤트 탭 자리에서 원래 순서대로 내보냄
```

- **완료 판정**: 입력 소스 변경 알림은 한 번의 전환에 여러 번 오거나 늦게 오기도 해서, 알림 횟수가 아니라
  "전환을 시작할 때의 입력 소스에서 실제로 바뀌었는지"로 판단합니다(알림 + 5ms 재확인, 최대 0.3초).
- **순서**: 전환이 끝난 순간 이미 탭 앞까지 와 있던 키가 보류분을 앞지르지 않도록, 보류분은 다음 탭 콜백(탭을 깨우는 배리어나
  먼저 온 키) 안에서 받은 이벤트보다 먼저 내보냅니다.
- **연타**: 전환 중에 다시 누른 Caps Lock도 순서대로 처리합니다. 한 번 누를 때마다 전환 단축키를 정확히 한 번 보냅니다.
- **시스템 설정을 바꾸지 않음**: 사용자가 이미 쓰는 ‘이전 입력 소스 선택’ 단축키(기본 ⌃Space)를 읽어서 그대로 합성합니다.
  F18 같은 기능키로 바꿔 둔 단축키도 그대로 씁니다.
- **비공개 API 없음**: HID 리매핑과 Caps Lock 상태(`IOHIDServiceClient`), 보조 키 설정 확인(IOKit 레지스트리), 이벤트 탭, TIS 알림,
  보안 입력 확인(`IsSecureEventInputEnabled`), `SMAppService` 모두 공개 API입니다.
- **개인정보**: 키 내용은 저장하거나 기록하지 않습니다. 보류는 전환이 끝날 때까지(보통 20~130ms, 전환 한 번에 길어야 약 0.35초)
  메모리에서만 합니다.
- **Caps Lock 켜짐 정리**: 매핑을 새로 걸 때 대문자 고정이 켜져 있으면 모든 키보드에서 끕니다(LED 포함).
  매핑한 뒤에는 Caps Lock으로 끌 수 없기 때문입니다.
- **원상복구**: 종료하면 mackor가 넣은 Caps Lock 매핑(과 DJI 수신기 매핑)만 지워 원래대로 돌아옵니다. 그 밖의 매핑은 건드리지 않습니다.
  다만 오른쪽 Command·Option·Control → F18 매핑은 공개 전 버전(0.2.0 이하)이 넣던 것과 같아서 누가 넣었든 mackor 것으로 보고,
  매핑을 걸거나 풀 때(보통 실행하자마자) 지웁니다.
- **보조 키 설정 감지**: 시스템 설정 › 키보드 › 키보드 단축키 › 보조 키에서 Caps Lock을 다른 동작으로 바꿔 둔 키보드는
  그 설정이 먼저 적용되어 매핑이 가려집니다. 이런 키보드는 메뉴와 설정 도우미가 알려 줍니다.
- **빠른 사용자 전환**: HID 매핑은 이 맥의 모든 사용자에게 걸리므로, 다른 사용자가 쓰는 동안에는 매핑을 풀고 돌아오면 다시 겁니다.
- **보안 입력 중에는 macOS에 맡김**: 어느 앱이든 보안 입력을 켜 두면(비밀번호 칸, 터미널의 "보안 키보드 입력", 보안 입력을 끄지 않고
  뒤로 간 앱) macOS는 **맨 앞 앱이 아니어도** 모든 이벤트 탭에서 키를 숨깁니다. 그대로 두면 Caps Lock이 아무 일도 하지 않으므로,
  mackor는 0.25초마다 보안 입력을 확인해 켜져 있는 동안 매핑을 풀어 macOS 기본 Caps Lock 전환(느린 쪽)에 맡기고, 꺼지면 다시 겁니다.

## gksdud와 비교

| | gksdud | mackor |
|---|---|---|
| 전환 직후 입력 | 전환 지연(20~130ms) 동안 씹힘 | 보류 후 순서대로 → 씹힘 없음 |
| 시스템 단축키 | F19로 변경(비공개 `activateSettings` 사용) | 변경 안 함(⌃Space 합성) |
| 배포 | 자체 서명 → 첫 실행 차단 | Developer ID 서명·공증 전제 |
| 상태 감시 | 1초 폴링 | 장치 연결·잠자기 해제 알림(보안 입력만 0.25초 확인) |

## 메뉴

메뉴 막대의 키보드 아이콘에서 로그인 시 자동 실행을 켜고 끌 수 있습니다.
**설정 도우미…** 는 소개 → 권한 허용 → 써 보기 → 완료 순서의 첫 실행 안내를 다시 엽니다.
아이콘이 가려져 보이지 않으면 mackor를 한 번 더 실행해도 열립니다.
실행 중에 권한이 꺼지면 아이콘에 경고가 붙고 설정 도우미가 권한 단계로 안내합니다.
Caps Lock을 한/영 키로 쓸 수 없는 키보드(Caps Lock에 다른 키 매핑이 있거나, 보조 키 설정이 가리는 경우)가 있으면 아이콘과 메뉴에
경고와 해결 방법이 붙습니다. 원인을 없앤 뒤 메뉴를 다시 열거나 설정 도우미로 돌아오면 다시 확인합니다.
보안 입력 때문에 macOS 기본 전환을 쓰는 동안에는 메뉴에 그 사실과 보안 입력을 켠 앱이 나옵니다(앱 이름은 IO 레지스트리의
`IOConsoleUsers`, 곧 `ioreg -l -w 0 | grep SecureInput`과 같은 값에서 읽습니다. 문서에 없는 키라 없으면 이름 없이 알립니다).
비밀번호를 칠 때마다 켜졌다 꺼지므로 아이콘은 바꾸지 않습니다.

## DJI 마이크 버튼

DJI Mic Mini·Mini 2 수신기를 USB-C로 꽂으면 송신기 버튼이 볼륨 올림 키로 들어옵니다. mackor는 이 수신기에서 온 볼륨 키만 Fn으로 바꿔,
Typeless처럼 Fn으로 받아쓰기를 켜고 끄는 앱을 마이크 버튼으로 쓸 수 있게 합니다(한 번 누르면 시작, 한 번 더 누르면 끝).
키보드의 볼륨 키는 그대로이고, 접근성 권한과 상관없이 동작합니다. 수신기를 다시 꽂아도 바로 다시 걸리고, mackor를 종료하면 원래대로 돌아옵니다.
기본으로 켜져 있으며, 수신기가 꽂혀 있을 때 메뉴의 **DJI 마이크 버튼을 Fn 키로**에서 끌 수 있습니다.
Fn을 누를 때 입력 소스가 바뀌거나 이모지 창이 뜨면 시스템 설정 › 키보드의 ‘🌐 키를 눌러’를 ‘아무 작업 안 함’으로 바꾸세요.

## 알려진 한계

- mackor가 켜져 있는 동안 Caps Lock으로 대문자를 고정할 수 없습니다. 대문자는 Shift로 입력하세요.
  mackor를 종료하면 Caps Lock이 원래대로 돌아옵니다.
- Caps Lock에 이미 다른 키 매핑(hidutil, 키 매핑 앱 등)이 있는 키보드에서는 동작하지 않습니다.
  mackor는 다른 매핑을 덮어쓰지 않으니 그 매핑을 먼저 지워 주세요. 지금 매핑은
  `hidutil property --matching '{"PrimaryUsagePage":1,"PrimaryUsage":6}' --get UserKeyMapping`으로 볼 수 있습니다(Caps Lock은 `30064771129`).
- 시스템 설정 › 키보드 › 키보드 단축키 › 보조 키에서 Caps Lock을 다른 동작으로 바꿔 둔 키보드에서는 그 설정이 먼저 적용되어
  동작하지 않습니다. ‘⇪ Caps Lock’으로 되돌리면 바로 적용됩니다. 거꾸로 다른 키(예: Control 키)를 ‘⇪ Caps Lock’으로 바꿔 두었다면
  mackor가 켜져 있는 동안 그 키도 한/영 키가 됩니다. Caps Lock과 Control을 맞바꿔 두었다면 Control 키도 ‘⌃ Control’로 함께 되돌리세요.
- **보안 입력 중**(비밀번호 칸, 터미널의 "보안 키보드 입력", 보안 입력을 끄지 않고 뒤로 간 앱)에는 mackor가 키를 볼 수 없어
  macOS 기본 Caps Lock 전환으로 돌아갑니다. 그동안은 mackor를 쓰기 전처럼 전환이 늦고 전환 직후 친 글자가 이전 언어로 들어갈 수 있습니다.
  시스템 설정의 ‘Caps Lock 키로 ABC 입력 소스 전환’을 꺼 두었다면 그동안 Caps Lock은 대문자 고정 키로 동작합니다.
  보안 입력이 켜진 뒤 매핑을 풀기까지 최대 0.25초 동안은 Caps Lock이 아무 일도 하지 않습니다.
- 입력 소스가 3개 이상이면 macOS의 "이전 입력 소스" 규칙대로 최근 두 입력 소스 사이를 오갑니다.
- 전환이 끝나기도 전에 Caps Lock을 몇 번씩 이어 누르면(수십 ms 간격의 연타) macOS가 전환 단축키 하나를 드물게 무시해
  한/영이 한 번 어긋날 수 있습니다. 이때 그 전환의 보류분은 0.3초 뒤 이전 언어로 나갑니다.
- 전환 중 보류된 키는 전환이 끝난 순간 맨 앞 앱으로 갑니다. 그 사이(보통 20~130ms)에 다른 앱을 클릭하면 새 앱에 입력됩니다.
- 강제 종료(`kill -9`)나 비정상 종료로 끝나면 매핑이 남아 Caps Lock이 아무 동작도 하지 않습니다.
  mackor를 다시 실행하면 한/영 키로 돌아오고, 재부팅하면 매핑이 사라집니다.
- hidutil이나 LaunchAgent로 Caps Lock 또는 오른쪽 Command·Option·Control → F18 매핑을 직접 걸어 두었다면, mackor는 그 매핑을 자기 것으로 봅니다.
  Caps Lock 매핑은 종료할 때 지우고, 오른쪽 키 매핑은 매핑을 걸거나 풀 때(보통 실행하자마자) 지우며 종료해도 되살리지 않습니다.
  mackor를 쓰는 동안에는 Caps Lock으로 전환하므로 그 설정은 지워도 됩니다.
- PC용 한국어 키보드의 한/영 키(LANG1)는 지원하지 않습니다. Caps Lock을 쓰세요.

## 개발

빌드와 테스트에는 Xcode 16 이상이 필요합니다. Command Line Tools만으로는 SwiftUI·swift-testing 매크로 플러그인이 없어
`swift build`·`swift test`가 실패하니, `xcode-select -p`가 CommandLineTools를 가리키면 `sudo xcode-select -s /Applications/Xcode.app`으로 바꾸세요.

```sh
swift test            # 순수 로직 단위 테스트 (전환 게이트, 단축키 해석, 키 매핑, DJI 마이크 버튼, 설정 도우미 단계)
scripts/e2e.sh        # 실제 애플 한국어 입력기로 종단 간 검증 (터미널에 접근성 권한 필요, 실행 중 손대지 말 것)
scripts/build.sh      # build/mackor.app (유니버설, 기본 ad-hoc 서명)
scripts/install.sh    # /Applications 에 설치 후 실행 (brew 설치 뒤 첫 실행 흐름 재현)
scripts/uninstall.sh  # 종료·키 매핑 복구·앱과 권한 항목 삭제
```

e2e는 F18을 직접 보내 검증합니다. Caps Lock → F18 HID 리매핑 경로는 실제 키보드로 따로 확인하세요.
e2e 환경 변수: `E2E_ONLY`(사례 고르기), `E2E_REPEAT`(반복), `MACKOR_ARGS`(mackor 인자), `MACKOR_BIN`(다른 빌드), `E2E_TRACE=1`(실험 창 기록),
`E2E_LOG`(로그 파일), `MACKOR_E2E_DIAG=1`(진단 사례).

디버그 실행: `swift build && .build/debug/mackor --no-remap` (실제 키보드 매핑은 건드리지 않음).
설정 도우미 확인: `--onboarding`(또는 `--onboarding=permission|try|done`)으로 바로 띄웁니다. 터미널에서 띄운 디버그 빌드는
터미널의 접근성 권한을 물려받아 항상 허용됨으로 보이므로, 권한 없는 화면은 `--simulate-untrusted`로 보고
`kill -USR1 <pid>`로 허용·해제를 흉내 냅니다. 이벤트 탭이 켜지는 실행 전에는 설치본을 종료하세요(두 인스턴스가 함께 전환함).
로그: `/usr/bin/log stream --level debug --predicate 'subsystem == "io.mackor.app"'` (전환 번호·시간, 입력 소스 ID, 보류 개수만 기록. 키 내용은 기록하지 않음).

### 배포

```sh
xcrun notarytool store-credentials mackor-notary   # 한 번만
MACKOR_VERSION=0.3.1 \
MACKOR_SIGN_IDENTITY="Developer ID Application: 이름 (팀ID)" \
MACKOR_NOTARY_PROFILE=mackor-notary \
scripts/release.sh
```

나온 zip을 `v버전` 태그의 GitHub 릴리스로 올리고(예: `gh release create v0.3.1 build/mackor-0.3.1.zip`),
스크립트가 출력한 `version`·`sha256`을 `Casks/mackor.rb`에 반영해 tap 저장소(`ASDFGHoney/homebrew-tap`)에도 넣습니다.

## 라이선스

[MIT](LICENSE). 보안 문제는 [SECURITY.md](SECURITY.md)의 절차로 비공개 신고해 주세요.
