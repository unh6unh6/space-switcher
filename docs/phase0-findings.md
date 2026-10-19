# Phase 0 검증 결과

- 환경: macOS 27.0.1 (Apple Silicon), Xcode 27.0, 메인 디스플레이 1개, 데스크탑 2개
- 스크립트: `spike/spaces.swift`, `spike/switch.swift`, `spike/eventtap.swift` (`swift spike/<파일>`로 실행)
- 날짜: 2026-09-30

## 요약

| # | SPEC §2 가정 | 결과 |
|---|--------------|------|
| 1 | `CGSCopyManagedDisplaySpaces`로 Space 목록, `uuid`, `type` 조회 | ✅ 일치 |
| 2 | 첫 데스크탑 `uuid`가 빈 문자열일 수 있음 | ⚠️ 이 맥에서는 **비어 있지 않음**. `__main__` 매핑은 방어 코드로 유지 |
| 3 | 재배치·재부팅 후 `uuid` 유지 | ✅ 유지됨. 반면 `ManagedSpaceID`는 **바뀜** |
| 4 | `com.apple.symbolichotkeys` ID 118~133 = "데스크탑 N으로 전환" | ✅ 일치 (단, 존재하는 데스크탑 수만큼만 항목이 있음) |
| 5 | 합성 이벤트로 전환 | ✅ Ctrl+2, Ctrl+← 모두 동작 |
| 6 | CGEventTap으로 Option+E 소비, `flagsChanged`로 Option 뗌 감지 | ✅ 일치 |

## 1. Space 목록 (`spike/spaces.swift`)

```json
{
  "activeSpace": 3,
  "displays": [{
    "Current Space": { "id64": 3, "ManagedSpaceID": 3, "type": 0, "uuid": "276CC097-…" },
    "Display Identifier": "C811FC88-…",
    "Spaces": [
      { "id64": 3, "ManagedSpaceID": 3, "type": 0, "uuid": "276CC097-9F18-4FDA-BDCB-EDC5B1744BD0" },
      { "id64": 4, "ManagedSpaceID": 4, "type": 0, "uuid": "F19E4877-50CC-4C08-AEB0-0EDD56A35D93" }
    ]
  }]
}
```

- 키 구성은 SPEC 그대로: `ManagedSpaceID`/`id64`, `uuid`, `type`.
- `CGSGetActiveSpace` 값은 `ManagedSpaceID`와 같은 체계 (3, 4).
- 재부팅 비교용 스냅샷: `spike/spaces-before.json`.

## 3. 재배치 + 재부팅 후

데스크탑 2를 1 앞으로 드래그한 뒤 재부팅 (`spike/spaces-after.json`):

| | 1번 자리 | 2번 자리 |
|---|---|---|
| 전 | ID 3, `276CC097…` | ID 4, `F19E4877…` |
| 후 | ID 4, `F19E4877…` | ID 5, `276CC097…` |

- `uuid`는 데스크탑을 따라 이동하며 유지됨 → **이름 저장 키로 적합** ✅
- `ManagedSpaceID`는 재부팅 후 재할당됨 (`276CC097`: 3 → 5) → 런타임 전용. 저장하면 안 됨.
- 배열 순서가 새 배치를 반영 → "Desktop N" 산출 방식 그대로 유효.

## 결론

SPEC §2의 가정은 모두 성립. 설계 변경 없이 Phase 1 진행 가능. 구현 시 반영할 점:

1. symbolichotkeys에 항목이 없으면 꺼짐으로 간주 → Ctrl+←/→ 대체 경로 (79/81도 plist에서 읽기)
2. 전환·탭 모두 `AXIsProcessTrusted()` 사전 확인 (권한 없으면 조용히 실패하므로)
3. 이벤트 탭: autorepeat 구분, "Option 뗌"은 `maskAlternate` true→false 전이로 판정
4. `ManagedSpaceID`는 절대 저장하지 않음. 저장 키는 `uuid` (빈 값이면 `__main__`)

## 4. symbolichotkeys

```
118 {"enabled": true, "value": {"parameters": [65535, 18, 262144]}}   # Ctrl+1
119 {"enabled": true, "value": {"parameters": [65535, 19, 262144]}}   # Ctrl+2
120~133 (absent)
79  {"enabled": true, "value": {"parameters": [65535, 123, 8650752]}} # Ctrl+←
81  {"enabled": true, "value": {"parameters": [65535, 124, 8650752]}} # Ctrl+→
```

- `parameters` = [문자코드(65535=없음), 가상 키코드, 수식키 플래그]. 262144 = `0x40000` = `CGEventFlags.maskControl`.
- 화살표(79/81)는 플래그에 `0x800000`(`maskSecondaryFn`, 화살표 키 고유 플래그)이 더해진 `0x840000`.
- **구현 시사점:** 항목이 없으면(absent) "꺼짐"으로 보고 Ctrl+←/→ 대체 경로를 쓴다. 대체 경로도 79/81을 plist에서 읽는다.

## 5. 전환 (`spike/switch.swift`)

- 손쉬운 사용 권한 없이: 이벤트가 무시됨 (에러 없음, 전환 안 됨). → 앱은 `AXIsProcessTrusted()`로 사전 확인 필요.
- 권한 부여 후 Ctrl+2: `active before: 3 → after: 4` ✅
- Ctrl+← (ID 79, `swift spike/switch.swift left`): 왼쪽 데스크탑으로 이동 ✅
- 권한은 이벤트를 **보내는 프로세스의 책임 앱**(이번엔 Warp)에 부여해야 함.

## 6. 이벤트 탭 (`spike/eventtap.swift`)

TextEdit에서 Option+E 연타, Option+Shift+E 연타 후 Option 뗌:

```
890.372 flagsChanged option=true          # Option 누름
890.455 Option+E  -> CONSUMED             # ×4
891.877 flagsChanged option=true          # Shift 추가 (Option 유지)
892.027 Option+Shift+E  -> CONSUMED       # ×10
895.467 flagsChanged option=true          # Shift 뗌
895.488 flagsChanged option=false         # Option 뗌 → 순환 모드 확정 시점
```

- `.cgSessionEventTap` + `.defaultTap`으로 생성 성공. 손쉬운 사용 권한만으로 충분 (입력 모니터링 추가 요구 없음).
- `nil` 반환으로 소비 → TextEdit에 `´` 입력 안 됨 ✅
- 키를 누르고 있으면 autorepeat `keyDown`이 계속 들어옴 (Option+Shift+E ×10). **상태 머신 입력에서 autorepeat을 구분해야 함** → `.keyboardEventAutorepeat` 필드로 판별. 무시할지 순환에 포함할지는 Phase 4에서 결정.
- `flagsChanged`는 Shift, Cmd+Tab 등 다른 수식키 변화에도 옴 → "Option 뗌"은 `maskAlternate`가 true→false로 바뀐 순간으로 판정.
- 20초 동안 `tapDisabledBy*`는 발생하지 않음. 슬립/깨우기 후 재활성화는 Phase 4 수동 테스트에서 확인.

## 후속 발견 (Phase 4, 2026-09-30): 합성한 수식키가 눌린 채로 남음

- 증상: 스위처로 이동한 직후 Option+E를 누르면 가끔 "삑" 소리만 나고 패널이 안 뜸.
- 원인: flags에 Control을 넣은 keyDown을 `.cghidEventTap`에 보내면 시스템 수식키 상태에 Control이 **계속 남음**
  (3초 뒤에도 `0x040000`). event source(`hidSystemState`/`privateState`/nil)와 무관.
  → 다음 실제 Option+E가 Ctrl+Option+E로 도착 → 단축키 불일치로 통과 → 앱이 삑.
- 해결: 키를 보낸 뒤 해당 수식키의 key-up `flagsChanged` 이벤트(Control=59, Fn=63)를 추가로 전송
  (`Spaces/ModifierRelease.swift`). 앱 경유 전환 4회(Ctrl+N 3회, 화살표 1회) 모두 이후 상태 `0x000000` 확인.

## 후속 발견 (v0.2.0 스파이크, 2026-09-30): Mission Control은 AX로 조작 불가

- 목적: #1(데스크탑 추가), #9(제거)를 Mission Control의 "+" 버튼 / 제거 액션을 AX로 눌러 구현
- 결과: macOS 27.0.1에서 Dock AX 트리의 `AXGroup id=mc`("Mission Control")는 Mission Control이 열려 있어도
  **자식 요소 0개**. Ctrl+↑로 열기, `Mission Control.app` 실행, 화면 위쪽 호버로 데스크탑 줄 펼치기 모두 동일.
  Dock의 `AXWindows`도 0개. → 예전 macOS의 AppleScript 방식("Spaces Bar" 그룹의 버튼) 사용 불가.
- 스크립트: `spike/missioncontrol.swift`

## 후속 발견 (#16 스파이크, 2026-10-03): 범용 "새 창" 규칙

스크립트: `spike/newwindow.swift <bundle-id> [--close]`, `--classify`(누르지 않고 분류만). macOS 27.0.1.

**결과: 규칙 1~3 모두 현재 데스크탑에 새 창을 만들고 화면이 다른 데스크탑으로 넘어가지 않음.**
| 앱 · 상태 | 규칙 | 결과 |
|---|---|---|
| Warp · 켜짐(창 있음) | 3 메뉴 "New Window" | 현재 데스크탑, 0.2초 |
| Chrome · 켜짐(창은 **다른 데스크탑에만**) | 3 메뉴 "새 창" | 현재 데스크탑, 이동 없음, 0.2초 |
| MarkEdit · 켜짐 | 3 파일 메뉴 ⌘N "New" | 현재 데스크탑, 0.2초 |
| IntelliJ · 꺼짐 | 1 실행 | 현재 데스크탑, 0.4초 |
| TextEdit · 켜짐(창 없음) | 2 다시 열기 | 현재 데스크탑, 0.4초 |

**규칙을 다듬은 근거**
- ⌘N 의미가 앱마다 다름: Claude "새 채팅", IntelliJ "Generate…"(Code 메뉴), Notion 새 창은 ⌘⇧N → 단축키 직접 전송 불가, 메뉴 항목을 AX로 누름
- 이름만으로 찾으면 오탐: Finder "새로운 윈도우에서 열기 및 닫기", TextEdit "새로운 윈도우로 탭 이동" → **"새/New… + 창/윈도우/Window" 이름 AND 단축키 키가 N**일 때만 확실
- 한국어 TextEdit 새 문서는 "신규" → 단어 목록 다국어화, 그래도 언어 의존 → 파일 메뉴(2번째 메뉴)의 ⌘N을 **후보**로
- 앱 정보의 "문서 편집 앱"(CFBundleDocumentTypes Editor)은 구분에 못 씀: Claude도 Editor
- 메뉴 항목 AXIdentifier는 `_NS:345` 같은 무작위 값 → 사용 불가
- "창 있음" 판단은 어떤 Space에 속한 창만: TextEdit은 Space에 속하지 않는 숨은 창(694×64 등)이 있음

**분류 (`--classify`)**: 확실 = Finder, Notion, Warp, Chrome / 후보(확인 필요) = Claude "새 채팅"(오답), MarkEdit "New"(정답) / 단일 창 = 카카오톡, Discord, IntelliJ(켜져 있을 때)

## #27 라이브 편집 스파이크 (2026-10-07, `spike/livetext.swift`)

메모 오버레이(비활성 `NSPanel`) 안의 `NSTextView`로 "클릭하면 바로 입력 + 커서 줄만 원문"이 되는지 확인.

| 확인 | 결과 |
|---|---|
| 클릭 시 `NSApp.activate` + `makeKey` 후 `super.mouseDown` | 클릭한 자리에 커서, 입력 들어감. **한글 IME 조합 정상**(c d → "ㅊㅇ") |
| 활성화 없이 클릭만 | 판단 보류: 스크립트 앱이 이미 활성 상태로 시작해 비교 불가. 실제 앱은 FocusReturner 방식(위)으로 간다 |
| TextKit 1 `NSLayoutManagerDelegate.shouldGenerateGlyphs`에서 `.null` 글리프 | `## Heading` 84pt → 숨김 63pt = `Heading` 63pt. 기호가 **자리까지** 사라짐 |
| `characterIndex(for:in:)` → 줄 번호 | 정확 (체크박스 클릭 판정에 사용) |

주의: 스크립트가 합성 키를 보내므로 실행 전에 Finder를 앞에 둔다(입력이 새도 터미널로 가지 않게). `setAttributedString`으로 매번 새로 넣어야 이전 숨김 속성이 새 글자에 번지지 않는다.

## 메모 편집기 커서가 가끔 안 보임 (2026-10-12, `spike/caret.swift`)

- `NSTextInsertionIndicator`(macOS 14+ 커서)의 frame 폭은 줄 맨 앞·빈 줄에서 **0**, 줄 가운데에서 1. 기본 `NSTextView`도 같으므로 원인이 아님 (커서는 frame 밖으로 그려짐). `lineFragmentPadding`/inset을 바꿔도 같음
- 실제 오버레이에서 클릭·↑ 이동 9곳: 커서 표시는 매번 존재, hidden 아님, 앱 활성·키 창·first responder 모두 참
- 재현 못 한 남은 원인: macOS 14+ 협조적 활성화가 `NSApp.activate`를 거절하면 비활성 패널은 키 입력을 받지만 AppKit은 비활성 앱의 커서를 그리지 않음. 테스트 호스트·스크립트 앱은 비활성으로 만들 수 없어 확인 불가
- 대응: 편집기가 키 창의 first responder면 앱 활성과 무관하게 커서를 그림(`shouldDrawInsertionPoint`), 줄 재배치 후 커서 위치 갱신, 활성화가 거절되면 unified log(category `Focus`)에 기록

## 커서 재발 조사 (2026-10-19, #38)

- `log`는 zsh 내장 명령이라 `log show …`가 "too many arguments"로 실패한다. **`/usr/bin/log show …`** 로 실행할 것 (그동안 셸에서 로그가 안 보이던 이유)
- #30의 활성화 거절 로그(`Focus`)는 7일간 0건 → 협조적 활성화 거절은 원인이 아니었음
- 앱이 비활성이 되면 macOS가 `NSTextInsertionIndicator`를 숨기고(`displayMode` hidden) 패널도 키 창에서 빠짐. 이때는 입력도 안 들어오므로 "입력은 되는데 커서 없음"과 다름. `shouldDrawInsertionPoint`는 이 표시에 영향 없음
- 실제 `LiveMarkdownTextView`로 입력 · Enter · 한글 조합(marked text) · ↑↓ · 표/코드/체크박스 줄 · `setSource` · 크기/투명도 변경 · first responder 재지정을 기록 → 커서 항상 표시
- **커서 막대는 표시 위치 기준 x −1…+1pt**. `lineFragmentPadding = 0`이면 줄 맨 앞(x=0)에서 왼쪽 절반이 스크롤 영역 경계에 잘려 1pt만 남음 → `textContainerInset.width = 1`로 해결(`LiveMarkdownCaretTests.testLineStartCaretIsNotClipped`)
- 재현 못 한 나머지는 자가 점검으로 대응: 편집기가 키보드를 가졌는데 커서가 숨겨져 있으면 log(category `Caret`)에 상태를 남기고 다시 표시

## 후속 발견 (2026-10-20): Mission Control 위에 데스크탑 이름 띄우기 스파이크
- 목적: Mission Control에서 어느 썸네일이 어느 데스크탑인지 보이게 우리 이름을 겹쳐 그리기 (`spike/mcoverlay.swift`)
- macOS 27에서 Mission Control은 Dock이 아니라 **WindowManager** 프로세스가 그림. `CGWindowListCopyWindowInfo`로 보임 (화면 기록 권한 없이 bounds · layer · owner 읽힘)
  - 열림: layer 19 전체 화면 + layer 14 `0,0 1920x96`(접힌 데스크탑 줄). 닫힘: 둘 다 사라짐 → 0.1 s 폴링으로 열림/닫힘 감지 가능
  - 데스크탑 줄 펼침(위쪽 호버): layer 14가 `1920x226`으로 커지고, 썸네일마다 layer 15 `190x129` 창이 y=37에 나타남(위에서 미끄러져 들어옴). 두 썸네일 간격 192, 묶음 가운데 = 화면 가운데
  - 창 썸네일은 layer 0(앱 이름표 layer 2)으로 따로 나타남
- 우리 패널: `.canJoinAllSpaces`만으로는 Mission Control 중 화면 목록에서 빠짐(메모 오버레이 포함). **`.stationary`를 더하면 남고, level 101에서 Mission Control 위 · 썸네일 위에 그려짐** (사용자 눈으로 확인)
- 미확인: 펼친 줄에 데스크탑 수만큼 layer 15 창이 생기는지(측정 때 2개만 보임), 접힌 줄의 이름 위치 계산, 여러 모니터
