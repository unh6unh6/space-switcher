# SpaceSwitcher

macOS 데스크탑(Spaces)에 이름을 붙이고, **Option+E** 한 번으로 골라서 이동하는 메뉴바 앱.

- 메뉴바에 지금 위치와 이름 표시 (예: `○ ● ○ 업무`, 설정에서 이름만·번호만 등으로 변경)
- **Option+E 짧게** → 데스크탑 목록 창. ↑↓ / 숫자 / Enter로 이동. 줄마다 그 데스크탑에 열린 앱 아이콘
- **Option 누른 채 E 반복** → 선택이 한 칸씩 넘어가고, Option을 떼면 그 데스크탑으로 이동
- 데스크탑을 옮기면 화면 가운데에 이름이 잠깐 표시 (설정에서 끄기·시간·위치 변경)
- 이름은 데스크탑을 따라다님 (순서를 바꾸거나 재부팅해도 유지)
- **데스크탑별 메모**: 지금 데스크탑의 메모가 화면 구석에 항상 떠 있음. 클릭해서 바로 입력, 마크다운(체크박스·표·이미지)이 그 자리에서 보기 좋게 표시됨. Option+E 목록 옆에도 미리보기
- 권한이 꺼지거나 단축키가 막히는 등 문제가 생기면 메뉴바 말풍선으로 알려주고 해결 버튼 제공

macOS 14 Sonoma 이상 · Apple Silicon / Intel 모두 지원

---

## 설치 (약 5분)

### 방법 A: Homebrew (권장, 한 줄)

```sh
brew install --cask unh6unh6/tap/spaceswitcher
```

"그래도 열기" 과정 없이 바로 열립니다. 설치 후 아래 **3번(권한)**부터 하면 됩니다.
업데이트는 `brew upgrade --cask spaceswitcher`, 삭제는 `brew uninstall --cask --zap spaceswitcher`.

> 이 방식은 설치할 때 macOS의 "확인되지 않은 개발자" 표시를 지웁니다 (앱이 Apple 공증을 받지 않았기 때문).
> 이 저장소를 믿는 경우에만 사용하세요.

### 방법 B: 직접 다운로드

### 1. 다운로드

[**Releases**](https://github.com/unh6unh6/SpaceSwitcher/releases/latest)에서 `SpaceSwitcher-x.y.z.dmg`를 받아 엽니다.
창에 나오는 **SpaceSwitcher**를 옆의 **Applications** 폴더로 드래그합니다.

### 2. 처음 실행 허용

이 앱은 Apple 유료 개발자 계정 없이 배포해서, 처음 열 때 macOS가 막습니다. **한 번만** 허용하면 됩니다.

1. Applications 폴더에서 SpaceSwitcher를 엽니다 → "열 수 없음" 경고가 뜨면 **완료**를 누릅니다
2. **시스템 설정 → 개인정보 보호 및 보안**으로 갑니다
3. 아래쪽 "SpaceSwitcher이(가) 차단되었습니다" 옆의 **그래도 열기**를 누르고, 암호를 입력합니다

> 터미널이 익숙하다면 대신 이 한 줄로도 됩니다:
> `xattr -dr com.apple.quarantine /Applications/SpaceSwitcher.app`

### 3. 손쉬운 사용 권한 켜기

앱이 뜨면 안내 창이 나옵니다. **권한 요청** → 시스템 설정에서 **SpaceSwitcher** 스위치를 켭니다.
몇 초 안에 안내 창의 1번이 ✅로 바뀌면 끝입니다. (키 입력을 받고 데스크탑 전환 키를 보내는 데 필요합니다)

### 4. "데스크탑 N으로 전환" 단축키 켜기 (권장)

**시스템 설정 → 키보드 → 키보드 단축키… → Mission Control**에서 "데스크탑 1로 전환", "데스크탑 2로 전환" … 을 모두 체크합니다.

- 데스크탑이 여러 개 있어야 이 항목들이 보입니다 (`Ctrl+↑` → 화면 위 **+** 로 추가)
- 꺼져 있어도 동작하지만, 옆 데스크탑으로 한 칸씩 넘어가서 느립니다

### 5. 로그인 시 자동 실행 (선택)

메뉴바 → **설정…** → 일반 → **로그인 시 자동 실행** 켜기

---

## 사용법

| 동작 | 방법 |
|------|------|
| 목록 열기 | **Option+E** 짧게 |
| 선택 이동 | ↑ ↓ 또는 E / Shift+E |
| 이동 | **Enter** 또는 항목 클릭 |
| 번호로 바로 이동 | **1–9** |
| 빠르게 순환 | Option을 누른 채 E 반복 → Option 떼기 (Shift+E는 거꾸로) |
| 이름 바꾸기 | 목록에서 **R** 또는 더블클릭 · 메뉴바 → "현재 데스크탑 이름 변경…" |
| 닫기 | **Esc** 또는 창 밖 클릭 |

| 메모 미리보기 편집 | 목록에서 **D** → 입력 → **Esc** 로 끝 (자동 저장) |
| 메모 미리보기 스크롤 | **Shift+↑ / ↓** |

**설정** (메뉴바 → 설정… 또는 ⌘,)

| 탭 | 내용 |
|----|------|
| 일반 | 로그인 시 자동 실행 · 메뉴바 표시 방식(이름/번호/점) · 이동 시 이름 표시 · 앱 아이콘 · 처음 선택(현재/직전 데스크탑) |
| 단축키 | 스위처 단축키 변경 (기본 ⌥E) |
| 데스크탑 | 데스크탑 이름 일괄 편집 |
| 메모 | 저장 폴더 · 메모 띄우기 on/off · 투명도 · 위치 · 배경색 · Option+E 미리보기 |
| 권한 | 손쉬운 사용 · 데스크탑 전환 단축키 상태 |

전체화면 앱 화면은 목록에 나오지 않습니다 (위에서 목록을 띄우는 건 가능).

### 메모

메뉴바 → **메모 띄우기**로 켜고 끕니다. 메모는 데스크탑마다 따로이고, 데스크탑을 옮기면 그 데스크탑의 메모로 바뀝니다.

- **클릭하면 바로 입력**, 입력을 멈추면 자동 저장. **Esc**로 원래 앱에 키보드를 돌려줌
- 커서가 있는 줄만 마크다운 원문이 보이고, 나머지 줄은 꾸며진 모양으로 표시 (제목·굵게·목록·인용·코드)
- 체크박스(`- [ ] 할 일`)는 클릭으로 체크
- 표(`| 항목 | 상태 |`)는 칸과 테두리로, 이미지(`![](경로)`)는 그림으로 표시. Finder에서 이미지를 끌어다 놓거나 스크린샷을 ⌘V로 붙여 넣으면 메모 폴더의 `images/`에 복사돼 들어감
- 편집 단축키 (한글 입력 중에도 동작)

  | 키 | 동작 |
  |----|------|
  | ⌘B / ⌘I / ⌘E | 굵게 / 기울임 / 코드 (다시 누르면 해제) |
  | ⌘K | 링크 |
  | ⌘L | 체크박스 만들기 · 체크 토글 |
  | Enter | 목록·체크박스·번호·인용 이어 쓰기 (빈 항목에서 누르면 목록 끝) |
  | Tab / Shift+Tab | 목록 들여쓰기 / 내어쓰기 |

- 메모 창 위쪽 버튼: 🔒 **읽기 전용 잠금**(데스크탑별) · **접기**
- 드래그로 옮기고 가장자리로 크기 조절. 위치·크기·접기·스크롤은 데스크탑마다 기억 (재시작해도 유지)
- 메모는 데스크탑마다 `이름.md` 파일 하나로 저장 (기본 `~/Library/Application Support/SpaceSwitcher/Memos`, 설정 → 메모에서 변경). 다른 편집기에서 고쳐도 바로 반영

---

## 업데이트

Homebrew로 설치했다면 `brew upgrade --cask spaceswitcher`.

직접 설치했다면 새 버전 DMG를 받아 Applications 폴더에 **덮어쓰기** 하면 됩니다. 권한과 이름은 그대로 유지됩니다.
(덮어쓰기 전에 메뉴바 → SpaceSwitcher 종료)

## 삭제

Homebrew: `brew uninstall --cask --zap spaceswitcher` (이름·설정·기본 폴더의 메모까지 삭제)

직접 설치:
1. 메뉴바 → **SpaceSwitcher 종료**
2. Applications 폴더에서 SpaceSwitcher를 휴지통으로
3. (선택) 저장된 이름·메모 지우기: Finder → 이동 → 폴더로 이동 → `~/Library/Application Support/SpaceSwitcher` 삭제 (메모 폴더를 바꿨다면 그 폴더도)
4. (선택) 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 목록에서 SpaceSwitcher 제거

## 문제 해결

- **Option+E를 눌러도 반응이 없음** → 메뉴바 이름 앞에 경고 표시가 있으면 손쉬운 사용 권한이 꺼진 것. 설정… → 권한 탭 확인
- **이동이 느림 / 한 칸씩 넘어감** → 위 4번 단축키가 꺼져 있음
- **단축키는 켜져 있는데 번호로 바로 이동이 안 됨** → macOS Dock이 단축키를 무시하는 상태. 메뉴바 → **Dock 다시 시작…** (이 상태일 때만 메뉴에 나타남. 그동안은 한 칸씩 넘어가는 방식으로 대신 이동)
- **메뉴바에 말풍선이 뜸** → 말풍선 안내와 버튼대로 해결. 다시 보고 싶지 않으면 **다시 보지 않기**
- **업데이트 후 권한이 풀림** → 손쉬운 사용 목록에서 SpaceSwitcher를 −로 지우고 다시 추가

---

## 개발

Swift / AppKit + SwiftUI, 외부 의존성 없음. 설계는 [`SPEC.md`](SPEC.md)와 [`docs/DECISIONS.md`](docs/DECISIONS.md)(SPEC과 달라진 결정), 개발 환경은 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), 진행 중인 작업은 [GitHub 이슈](https://github.com/unh6unh6/SpaceSwitcher/issues).

```sh
brew install xcodegen
xcodegen generate
xcodebuild test -scheme SpaceSwitcher -destination 'platform=macOS'
./scripts/install.sh            # Release 빌드 → /Applications 설치
./scripts/release.sh x.y.z      # 버전 올리고 DMG 만들어 GitHub Release 게시 + Homebrew tap 갱신
```

빌드는 키체인의 자체 서명 인증서 **SpaceSwitcher Signing**(코드 서명용)으로 서명합니다.
직접 빌드하려면 같은 이름의 인증서를 만들거나 `project.yml`의 `CODE_SIGN_IDENTITY`를 바꾸세요.
Spaces 조회에 macOS 비공개 API(`CGSCopyManagedDisplaySpaces`)를 사용하므로 App Store 배포는 불가합니다.
