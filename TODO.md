# SpaceSwitcher TODO

> **MVP(Phase S~7) 완료 · v0.1.0 릴리스됨.** 이 파일은 기록용. 이후 작업은 [GitHub 이슈](https://github.com/unh6unh6/space-switcher/issues).

> 표시: 👤 = 사용자가 직접 해야 함 (GUI 조작, 비밀번호, 권한 부여) · 🤖 = Claude가 함 · ⏱ = 예상 시간
> 한 Phase가 끝나면 커밋: `phaseN: <요약>`. 상세 동작은 `SPEC.md` 참고.

## 확정된 결정

→ [`docs/DECISIONS.md`](docs/DECISIONS.md)로 이동 (SPEC보다 우선).

---

## Phase S — 개발 환경 준비 ⏱ 약 1시간 (대부분 Xcode 다운로드 대기)

현재 상태: Xcode 없음, xcodegen 없음, 서명 인증서 0개, GitHub 원격 없음.

- [x] 👤 App Store에서 **Xcode** 설치 (약 10GB, 30~60분)
- [x] 👤 터미널: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- [x] 👤 터미널: `sudo xcodebuild -license accept` → Xcode 한 번 실행해 추가 구성요소 설치
- [x] 🤖 `brew install xcodegen`
- [x] 👤 자체 서명 인증서 만들기 (약 5분, Claude가 단계 안내)
  - 키체인 접근 → 메뉴 "인증서 지원" → "인증서 생성…"
  - 이름 `SpaceSwitcher Signing`, 신원 유형 "자체 서명 루트", 인증서 유형 "코드 서명"
- [x] 🤖 `security find-identity -v -p codesigning`으로 인증서 인식 확인
- [x] 👤 인증서를 `.p12`로 내보내 안전한 곳(비밀번호 관리자 등)에 백업
  - 잃어버리면 지인들이 업데이트할 때마다 권한을 다시 줘야 함
- [x] 👤 시스템 설정 → 키보드 → 키보드 단축키 → Mission Control → **"데스크탑 N으로 전환" 켜기** (데스크탑을 2개 이상 만들어 둔 상태에서)
- [x] 🤖 `.gitignore` 작성 (`*.xcodeproj`, `build/`, `DerivedData/`, `*.p12`, `.DS_Store`)
- [x] 🤖 첫 커밋: `SPEC.md`, `CLAUDE.md`, `TODO.md`, `.gitignore`

**완료 조건:** `xcodebuild -version`이 출력되고, 인증서가 1개 보임. (GitHub 저장소는 Phase 7로 연기)

---

## Phase 0 — 검증 스파이크 ⏱ 약 1~2시간 (수동 확인 포함)

SPEC §2의 가정이 실제 맥(macOS 27)에서 맞는지 확인. **틀린 게 나오면 여기서 멈추고 논의.**

- [x] 🤖 `spike/` 폴더에 Swift CLI 스크립트 작성 (앱 본체와 분리, 나중에 삭제 가능)
- [x] 🤖 `CGSCopyManagedDisplaySpaces` 결과를 JSON 출력 → `uuid`, `type`, 첫 데스크탑 uuid 값 확인
- [x] 👤 데스크탑 순서를 바꾸고 재부팅 → 🤖 uuid가 유지되는지 다시 출력해 비교
- [x] 🤖 `defaults export com.apple.symbolichotkeys -`로 ID 118~133 구조 확인
- [x] 👤 터미널에 손쉬운 사용 권한 부여 → 🤖 합성한 `Ctrl+2` 이벤트로 데스크탑 2 전환 확인
- [x] 🤖 CGEventTap으로 `Option+E` 소비 + `flagsChanged`로 Option 뗌 감지 확인
- [x] 🤖 결과를 `docs/phase0-findings.md`에 기록하고 요약 보고

**완료 조건:** findings 문서 작성, 가정이 모두 맞거나 대안에 합의.

---

## Phase 1 — 앱 골격 + 메뉴바 ⏱ 약 2시간

- [x] 🤖 `project.yml` 작성: 번들 ID, macOS 14, `LSUIElement`, 샌드박스 끔, 서명 `SpaceSwitcher Signing` (Manual)
- [x] 🤖 `xcodegen generate` → 빈 앱 빌드 성공
- [x] 🤖 `CGSPrivate.swift`, `Space` 모델, `SpaceProvider` (+ `SpaceParser` 테스트 7개)
- [x] 🤖 `activeSpaceDidChangeNotification` 구독
- [x] 🤖 메뉴바에 `데스크탑 N` 표시 + 목록 메뉴 (전환은 아직 없음) + 종료 메뉴
- [x] 👤 앱 실행 → 데스크탑 바꿔서 메뉴바 표시가 바뀌는지 확인 (SPEC §7 Spaces/메뉴바 항목)

**완료 조건:** 데스크탑을 바꾸면 메뉴바 표시가 즉시 바뀐다.

---

## Phase 2 — 전환 + 권한 ⏱ 약 3시간

- [x] 🤖 `SymbolicHotKeys` (plist에서 키코드/수식키 읽기)
- [x] 🤖 `SpaceSwitcherService`: Ctrl+N 경로
- [x] 🤖 `SpaceSwitcherService`: Ctrl+←/→ 대체 경로 (단축키 꺼짐 / 17번 이후)
- [x] 🤖 온보딩 창: 손쉬운 사용 권한 요청 + 폴링, 단축키 꺼짐 안내
- [x] 🤖 권한 없을 때 메뉴바 아이콘 경고
- [x] 🤖 메뉴 항목 클릭 → 전환
- [x] 👤 수동 확인: 권한 없이 첫 실행 → 온보딩 / 메뉴로 전환 / 단축키를 끈 상태로 전환 / 재빌드 후에도 권한 유지

**완료 조건:** 메뉴에서 아무 데스크탑이나 골라 이동. 단축키가 꺼져 있어도 대체 경로로 이동.

---

## Phase 3 — 이름 ⏱ 약 2시간

- [x] 🤖 `NameStoreTests` 먼저 작성 (30자 제한, 공백 제거, 빈 문자열=삭제, `__main__`, 사라진 uuid 보관)
- [x] 🤖 `NameStore` 구현 → 테스트 통과 (`names.json`)
- [x] 🤖 메뉴 "현재 데스크탑 이름 변경…" 입력 창
- [x] 🤖 메뉴바/메뉴 목록에 이름 반영
- [x] 👤 수동 확인: 이름 붙이고 앱 재시작 → 유지 / 재부팅 → 유지
- [x] 👤 수동 확인: 이름 붙인 데스크탑을 Mission Control에서 다른 자리로 옮김 → 이름이 데스크탑을 따라감 (번호만 바뀜)

**완료 조건:** 이름이 재시작·재부팅 후에도 유지된다.

---

## Phase 4 — 스위처 ⏱ 약 반나절~하루 (가장 큼)

- [x] 🤖 `SwitcherStateMachineTests` 먼저 작성 (SPEC §3.1 모든 전이)
- [x] 🤖 `SwitcherStateMachine` 구현 → 테스트 통과
- [x] 🤖 `MRUTrackerTests` → `MRUTracker` 구현
- [x] 🤖 `EventTap` (Option+E 하드코딩, 재활성화 처리) + `KeyMapper` 테스트, 꾹 누름(autorepeat) 무시
- [x] 🤖 `SwitcherPanel` + `SwitcherView` (중앙, 반투명, 모든 Space에 표시)
- [x] 🤖 팝업 모드 · 순환 모드 연결
- [x] 🤖 숫자키 즉시 전환, R/더블클릭 인라인 이름 편집
- [x] 👤 SPEC §7 "스위처" 항목 8개 전부 수동 확인
- [x] 🤖 버그: 이동 직후 Option+E가 삑 소리만 나고 안 뜸 → 합성 Ctrl이 눌린 채 남던 문제 수정 (`ModifierRelease`)
- [x] 🤖 초기 선택을 현재 데스크탑으로 변경 (`InitialSelection`, 기본값 current)
- [x] 👤 수동 확인: 이동 직후 바로 Option+E → 삑 소리 없이 뜸 / 첫 선택이 현재 데스크탑

**완료 조건:** SPEC §7 스위처 항목 전부 통과.

---

## Phase 5 — 설정 ⏱ 약 3~4시간

- [x] 🤖 설정 창 골격 (일반 / 단축키 / 데스크탑 / 권한 탭)
- [x] 🤖 단축키 레코더 + 저장 + 이벤트 탭 즉시 반영 + 기본값 복원
- [x] 🤖 로그인 시 자동 실행 (`SMAppService`)
- [x] 🤖 스위처 첫 선택: 현재 데스크탑 / 직전 데스크탑 선택 옵션 (`InitialSelection.store`)
- [x] 🤖 데스크탑 탭: 이름 편집 + 사용하지 않는 이름 정리
- [x] 🤖 권한 탭: 상태 표시 + 시스템 설정 열기 버튼
- [x] 👤 수동 확인: 설정에서 단축키를 `Ctrl+Option+Space`로 녹화 → 동작 → 기본값 복원
- [x] 👤 수동 확인: 첫 선택 "직전 데스크탑"으로 바꿔 동작 확인
- [x] 👤 수동 확인: 자동 실행 켜기 → 로그아웃 → 로그인 후 메뉴바에 앱이 있음

**완료 조건:** 단축키를 바꿔도 스위처가 똑같이 동작. 로그인 후 자동 실행됨.

---

## Phase 6 — 내 맥에 설치 ⏱ 약 30분

- [x] 🤖 `scripts/install.sh`: Release 빌드 → `/Applications/SpaceSwitcher.app`에 복사 → 실행
- [x] 👤 `./scripts/install.sh` 실행 → 손쉬운 사용 권한 부여 (Claude가 실행, 인증서 덕에 권한 그대로 유지됨)
- [x] 👤 설치된 앱 설정에서 "로그인 시 자동 실행" 껐다 켜기 → 재부팅 후 자동 실행 + Option+E 확인

**완료 조건:** 재부팅 후 앱이 자동으로 뜨고 Option+E가 동작.

---

## Phase 7 — 지인 배포 ⏱ 약 2시간 (최초), 이후 릴리스마다 약 5분

- [x] 🤖 `git branch -m main` → `gh repo create unh6unh6/space-switcher --public --source . --push` (Phase S에서 연기됨, 실행 전 사용자 확인)
- [x] 🤖 `project.yml`에 버전 필드 정리 (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`)
- [x] 🤖 `scripts/release.sh <버전>`:
  - Universal(arm64+x86_64) Release 빌드
  - `SpaceSwitcher Signing`으로 서명 + `codesign --verify` 검사
  - `hdiutil`로 DMG 생성 (앱 + Applications 바로가기)
  - `gh release create v<버전> SpaceSwitcher.dmg`
- [x] 🤖 `README.md` (한국어): 기능 소개, 스크린샷 자리, **지인용 설치 방법**
- [x] 🤖 Homebrew tap: `unh6unh6/homebrew-tap` 생성, `scripts/cask.rb.template` (postflight_steps로 quarantine 제거, 로컬 tap 설치로 검증), release.sh 7단계에서 자동 갱신
  - DMG 열기 → Applications로 드래그
  - 첫 실행 차단 시: 시스템 설정 → 개인정보 보호 및 보안 → "그래도 열기"
  - 손쉬운 사용 권한 부여
  - "데스크탑 N으로 전환" 단축키 켜기
  - 업데이트: 새 DMG로 덮어쓰기 (권한 유지됨)
- [x] 👤 `./scripts/release.sh 0.1.0` 실행 → GitHub Releases 페이지 확인 (v0.1.0 게시됨)
- [x] 🤖 `brew install --cask unh6unh6/tap/spaceswitcher` 실제 설치 검증 (임시 appdir, quarantine 없음 확인)
- [ ] 👤 지인 1명에게 링크 전달 → README대로 설치되는지 확인 (가능하면 Intel 맥도)
- [ ] 🤖 지인 피드백 반영해 README 보완

**완료 조건:** 지인이 README만 보고 설치해 Option+E를 사용.

---

## 이후 작업 → GitHub 이슈 (2026-09-30부터)

MVP(Phase S~7) 이후의 기능 개선·버그는 이 파일이 아니라 **[GitHub 이슈](https://github.com/unh6unh6/space-switcher/issues)**로 관리한다.

- 이슈 여러 개를 **마일스톤**(예: [`v0.2.0`](https://github.com/unh6unh6/space-switcher/milestone/1))으로 묶어 릴리스 단위로 작업
- 커밋은 로컬에 쌓고 메시지에 `Closes #N` → 마일스톤이 끝나면 `./scripts/release.sh <버전>` (푸시되면서 이슈 자동 종료)
- 옮겨진 항목: #1 새 데스크탑 추가 · #2 다중 모니터 · #3 전체화면 앱 목록 · #4 아이콘 · #5 업데이트 알림 · #6 공증
