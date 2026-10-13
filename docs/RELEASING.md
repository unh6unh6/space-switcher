# 릴리스

마일스톤(예: `v0.2.0`)의 이슈가 모두 끝나면 **사용자가** 실행한다. 외부 공개 작업이라 Claude는 사용자 요청 없이 실행하지 않는다.

```sh
./scripts/release.sh 0.2.0 --dry-run   # DMG까지만. 커밋·푸시·게시 없음 (project.yml 자동 복구)
./scripts/release.sh 0.2.0             # 실제 릴리스
```

## release.sh가 하는 일

1. `project.yml`의 `MARKETING_VERSION` = 인자, `CURRENT_PROJECT_VERSION` += 1
2. 전체 테스트
3. Release 빌드 (Universal), `SpaceSwitcher Signing` 서명 검증
4. `build/release/SpaceSwitcher-<버전>.dmg` 생성(앱 + Applications 링크) + DMG 서명 → sha256 → `build/release/Casks/spaceswitcher.rb` 렌더링(`scripts/cask.rb.template`) + `brew style`
5. `release: v<버전>` 커밋 + 태그 + `git push origin main v<버전>` → 쌓여 있던 `Closes #N` 커밋이 이슈를 자동 종료
6. `gh release create` (DMG 첨부, 설치 안내 + 자동 생성 노트)
7. `unh6unh6/homebrew-tap`을 임시 클론 → `Casks/spaceswitcher.rb` 교체 → 푸시

실패 시: 5단계 커밋 전이면 `project.yml`은 자동 복구된다(trap).

## 릴리스 후

- 마일스톤 닫기: `gh api -X PATCH repos/unh6unh6/space-switcher/milestones/<번호> -f state=closed`
- 다음 마일스톤 만들기: `gh api repos/unh6unh6/space-switcher/milestones -f title=v0.3.0`
- 실제 설치 검증 (설치본을 건드리지 않게 임시 폴더로):
  ```sh
  brew install --cask --appdir="$TMPDIR/Apps" unh6unh6/tap/spaceswitcher
  xattr "$TMPDIR/Apps/SpaceSwitcher.app"      # com.apple.quarantine 이 없어야 함
  brew uninstall --cask spaceswitcher          # 주의: uninstall quit 이 실행 중인 앱을 종료함
  open /Applications/SpaceSwitcher.app
  ```

## 중간에 실패했을 때

| 어디서 | 상태 | 복구 |
|--------|------|------|
| 1~4 | 아무것도 안 나감 | 원인 고치고 다시 실행 |
| 5 푸시 후 6 실패 | 태그는 GitHub에 있음, 릴리스 없음 | `gh release create v<버전> build/release/SpaceSwitcher-<버전>.dmg --title "SpaceSwitcher <버전>" --generate-notes` 수동 실행 → 7단계 수동 |
| 7 실패 | 릴리스는 있음, tap이 옛 버전 | tap 클론 → `build/release/Casks/spaceswitcher.rb` 복사 → 커밋·푸시 |
| 같은 버전 다시 | 태그 중복으로 스크립트가 거부 | 패치 버전을 올려서 릴리스 (게시된 태그는 지우지 않는 것을 원칙으로) |

## Homebrew cask

- tap 저장소: `unh6unh6/homebrew-tap`, 사용자 표기 `unh6unh6/tap` (brew가 `homebrew-` 접두어를 생략)
- 템플릿: `scripts/cask.rb.template` (`{{VERSION}}`, `{{SHA256}}` 치환; `{{appdir}}`는 Homebrew 자체 템플릿이라 그대로 둠)
- Homebrew 최신 규칙: `postflight do` 금지 → **`postflight_steps`** 사용, `depends_on macos: :sonoma` 표기
- 공식 homebrew/cask 등록은 공증이 필요 (#6)
