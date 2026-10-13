# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

SpaceSwitcher is a macOS menu-bar agent app (`LSUIElement`, no Dock icon). It lets you name desktops (Spaces) and switch between them with an IntelliJ-style switcher (`Option+E`). It's written in Swift with AppKit and SwiftUI, has no external dependencies, and targets macOS 14+ as a universal binary.

**Answer the user in Korean.** This directory is its own git repo (`unh6unh6/space-switcher`, branch `main`). It is separate from any parent workspace.

## Start of every session

1. Skim the docs that apply to the task (see the table below).
2. Check the current state:
   - `git status -sb`. Unpushed commits are normal; they wait for the next release.
   - `gh issue list --milestone <next version>`, or plain `gh issue list`.
3. If you'll build or run the app, check the environment. `security find-identity -v -p codesigning` must list `SpaceSwitcher Signing`, and `xcodebuild -version` must work. If either fails, follow `docs/DEVELOPMENT.md` §1–2.

| Doc | Read when |
|-----|-----------|
| `SPEC.md` (Korean) | Original product spec: behavior (§3), structure (§4), manual checklist (§7). |
| `docs/DECISIONS.md` | **Overrides SPEC.** Every deviation: distribution, signing, initial selection, autorepeat, and more. Add new decisions here. |
| `docs/DEVELOPMENT.md` | New-Mac setup, the signing cert, the build/test/run loop, known noise and pitfalls, where data lives. |
| `docs/RELEASING.md` | Releasing, the Homebrew tap, recovering from a failed release. |
| `docs/MANUAL_TESTS.md` | After any change to permissions, hotkeys, Spaces, or UI. Pick the relevant items for the user to check. |
| `docs/phase0-findings.md` | Verified macOS behavior behind the private-API approach, including the stuck-Ctrl finding. Re-verify with `spike/` on a new macOS. |
| `TODO.md` | Historical MVP checklist (Phase S–7, all done). No new items. |

## Workflow: GitHub issues → milestone → release

- The MVP is shipped as v0.1.0 (GitHub Releases plus the Homebrew tap). All further work is **one GitHub issue per unit of work**.
  - If an issue doesn't exist yet, file one first: `gh issue create --label enhancement|bug`.
  - The body covers the goal, approach, risks, a checklist, and an estimate.
- **Priority** is a label: `priority: high` (must be in the next release), `priority: medium` (next release if time allows), `priority: low` (someday). The user sets it; ask if an issue has none. Pick work in this order: the next milestone's issues first, then by priority. `gh issue list --label "priority: high"`.
- **Experimental** features carry the `experimental` label (instead of a priority). In the app they stay behind **Settings → 실험적 기능** (default off) until promoted; promotion removes the toggle and is a normal issue.
- A **milestone is a release** (e.g. `v0.2.0`).
  - Work through its issues on `main`.
  - Commit locally at sensible checkpoints without asking.
  - Commit messages end with `Closes #N` plus the `Co-Authored-By` trailer.
- **Don't push mid-milestone.** When the milestone is done, the user runs `./scripts/release.sh <x.y.z>`. That pushes (which auto-closes the issues), publishes the Release, and updates the tap (`docs/RELEASING.md`).
- **Confirm with the user before anything outward-facing:** push, release, creating or deleting repos, creating issues they didn't ask for, editing published releases.
- If a platform assumption from SPEC §2 or phase0-findings turns out wrong, stop, report it, and ask. Don't work around it silently.

## Communicating with the user

The user asked for an ADHD-friendly style and is new to macOS app distribution.

- Lead with the next action. Use numbered steps, one action each, with concrete time estimates ("약 10분").
- Restate progress every turn (e.g. "#1: 3/5 done"). Make wins visible: say what works now and how to try it.
- No preamble, no recap, no closing pleasantries. Ask one question at a time. For real choices, use AskUserQuestion with the recommended option first.
- When the user must run a command, suggest `! <command>`. `sudo` can't prompt there, so point them to Terminal.app for anything that needs it.
- Don't use the `⚠︎` symbol in chat; their terminal renders it broken.
- Physical checks (permissions, reboot, real key presses) are the user's job. List exactly what to press and what they should see.

## Commands

```sh
xcodegen generate                         # after adding/removing files; .xcodeproj is gitignored, never edit it
xcodebuild test -scheme SpaceSwitcher -destination 'platform=macOS' -derivedDataPath build/DerivedData
#   one test: append -only-testing:SpaceSwitcherTests/<Class>/<method>
xcodebuild -scheme SpaceSwitcher -configuration Debug -derivedDataPath build/DerivedData build
swift scripts/smoke.swift                 # running app: panel opens <100ms, Sticky, Esc (terminal needs Accessibility)
./scripts/install.sh                      # Release build → /Applications, relaunch
./scripts/release.sh x.y.z [--dry-run]    # user-run; see docs/RELEASING.md
```

Editor diagnostics such as `No such module 'XCTest'` or `Cannot find type …` are SourceKit noise. Trust xcodebuild.

## Architecture (read SPEC §2 and phase0-findings before touching Spaces/Hotkey)

macOS has no public Spaces API, so the app combines three mechanisms.

1. **Reading Spaces** (`Spaces/`):
   - Private CGS functions, declared with `@_silgen_name` **only in `CGSPrivate.swift`**. `SpaceProvider` calls them.
   - `SpaceParser` (pure, tested) keeps the `type == 0` desktops of the main display:
     - `index` is the N in "Desktop N".
     - `position` is the slot among *all* Spaces, fullscreen ones included. The arrow fallback counts with it.
     - `id` is the `uuid`; an empty uuid becomes `__main__`.
     - Never persist `ManagedSpaceID`: it changes on reboot.
   - Changes arrive via `NSWorkspace.activeSpaceDidChangeNotification`. Add, remove, and reorder have no notification, so re-query whenever a menu or the panel opens.
2. **Switching**:
   - `SymbolicHotKeys` reads the "Switch to Desktop N" shortcuts from `com.apple.symbolichotkeys`. IDs are 118+N−1, and 79/81 for Ctrl+←/→. A missing entry means off.
   - `SwitchPlanner` (pure) picks direct, arrows×n, or none.
   - `SpaceSwitcherService` posts the `CGEvent`s, then posts modifier key-ups via `ModifierRelease`. Without them, synthesized Ctrl sticks and the next Option+E beeps.
   - Needs Accessibility. Without it, the events are dropped silently.
   - The Dock sometimes ignores "Switch to Desktop N" while Ctrl+←/→ still work (#22; `killall Dock` fixes it). A direct switch is verified within 0.7 s; on failure the trip finishes with arrows (`SwitchPlanner.followUp`), later switches skip direct (`avoidDirect`), and the menu bar / permissions view offer "Dock 다시 시작" (`DockRestart`). Debug hook: UserDefaults `debugSimulateDockIgnoresShortcuts`.
3. **Global hotkey** (`Hotkey/`):
   - `EventTap` is a session `CGEventTap` on `keyDown` + `flagsChanged`, running on **its own thread** (#10: a stalled main thread made macOS bypass the tap). It re-enables itself after timeouts and on wake, and logs slow callbacks / disables to the unified log (subsystem = bundle ID). (Carbon hotkeys can't do Option-only combos on macOS 15+ and can't see a modifier being released.)
   - `KeyMapper` (pure) maps keys to switcher events and decides pass or consume. It ignores autorepeat of the shortcut key.
   - `Shortcut` handles validation, the UserDefaults key `switcherShortcut`, and a `didChange` notification.

**Switcher** (`Switcher/`):
- `SwitcherStateMachine` (pure; event in, action out) moves Idle → Holding → Sticky / Renaming / Describing per SPEC §3.1. Describing = D edits the selected desktop's memo in the preview (#20); Shift+↑↓ scrolls it (`scrollMemo`).
  - Releasing the modifier after 1 press enters Sticky (popup mode).
  - Releasing it after ≥ 2 presses switches (cycle mode).
- `SwitcherController` wires the tap, machine, `SwitcherPanel`, and stores together.
  - The machine, MRU, and shortcut live on the tap thread (reach them via `tap.perform`); UI lives on main. Actions cross to main with a snapshot of the desktop list.
  - It decides consumption synchronously in the tap callback and renders asynchronously.
  - Keys stay on the tap even in Sticky. Only inline rename activates the app.
- `SwitcherPanel` is a non-activating `NSPanel` at `.popUpMenu` level with `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`. `SwitcherView` puts the memo preview (#20) to the right of the list, as tall as the list (min 240) so the panel never resizes while moving; `recenter()` after the preview appears for an edit.
- The initial selection comes from `InitialSelection` in `Store/MRUTracker.swift`: the current desktop by default, or the MRU previous one.

**Other components:**
- Per-desktop app icons in the switcher (#14): `Spaces/SpaceApps` (pure: filter layer-0, ≥50 px, regular apps; sort by window count) fed by `SpaceAppsProvider` (`CGWindowList` + `CGSCopySpacesForWindows`). UserDefaults `switcherShowAppIcons`. The controller warms the panel up at `start()` to keep the first open under 100 ms.
- `HUD/` shows the desktop name briefly on every Space change (#13): `SpaceHUDContent`/`SpaceHUDSettings` are pure (UserDefaults `hudEnabled`/`hudDuration`/`hudPosition`); `SpaceHUDPanel` is a click-through panel on all Spaces.
- `Store/NameStore` persists `names.json`: names (30 chars); an empty value deletes, unknown ids are kept. `legacyDescriptions` only exists to migrate unreleased #17 data.
- `Memo/` (#18): `MemoStore` keeps one Markdown file per desktop in a user-chosen folder (default `~/Library/Application Support/SpaceSwitcher/Memos`), named after the desktop and linked by `space: <uuid>` front matter (`MemoFormat`, pure); it watches the folder for outside edits. `MemoSettings` (pure, UserDefaults) holds overlay/preview toggles, opacity, corner, folder, and the overlay layout: per-desktop `layouts[Space.id]` (frame + collapsed, #24) with the shared `frame`/`collapsed` as fallback for new desktops and fullscreen Spaces — writers merge into the latest stored value. Scroll positions (#25): `MemoScrollMemory` (pure, UserDefaults `memoScrollOverlay`/`memoScrollPreview`, kept across restarts) keeps the first visible source line per desktop, separately for the overlay and the preview. Editing (#27): `Memo/LiveMarkdownEditor` (NSTextView on TextKit 1) keeps the Markdown source as its text and restyles it from `MarkdownLiveStyle` (pure) runs — away from the caret line, markers are null glyphs (`LiveMarkdownLayoutManager`) and bullets/checkboxes/rules/quote bars/code bands are drawn; the caret line shows its source dimmed. Shared by the overlay and the Option+E preview; `MarkdownBlocks.toggleTask` flips checkboxes. Typing autosaves 0.5 s after it stops; `MemoSync` (pure) tells our own writes from outside edits. `MemoSettings.locked` (UserDefaults `memoLocked`) makes a desktop's memo read-only. Markdown extensions (#21): `MarkdownEditing` (pure: ⌘B/I/E/K/L, list Enter/Tab as replacements; physical key codes so a Korean layout works), `MarkdownTables` (pure pipe tables; a caret in a table reveals all of it via `MarkdownLiveStyle.expand`), `MarkdownImages` (pure: image lines, path resolving against the memo folder, size ≤ width × 240). Tables and images are `LiveDrawing`s drawn in an enlarged line fragment (other table lines fold to ~0 height); anchor drawings on a character that is not hidden, because hidden line-start characters sit on the previous fragment. `LiveImageCache` loads local files (reloading on change) and web images (background, then `didLoad`). Dropped/pasted images are copied into `images/` in the memo folder. Backgrounds: `MemoSettings.Background` (standard HUD / white / black / yellow; `memoOverlayBackground`, overlay only) applied by `Memo/PanelBackground` (a tint view + window appearance for text contrast). `MemoOverlayController` shows the current desktop's memo in an always-on-top panel (`.statusBar` level, all Spaces); a click borrows the keyboard via `App/FocusReturner` (activate on mouseDown, verified with Korean IME), Esc gives it back to the previous app, a click elsewhere or a desktop change just lets go (`release`). In the switcher, D makes the preview editable in place (Describing); Esc/⌘Enter end it. Pending typing is flushed on desktop change, panel close and quit.
- `MenuBar/StatusItemController` shows the title and the menu, with a warning prefix when Accessibility is missing. The title comes from `MenuBarTitle` (pure; styles name / number+name / dots / dots+name / number, max name length; UserDefaults `menuBarStyle`/`menuBarMaxLength`) (#15).
- `Onboarding/PermissionMonitor` polls AX trust and missing desktop shortcuts every 1 s on a background queue, mirrors the #22 Dock state, and watches the Dock pid (a restart resets it — NSWorkspace posts nothing for the Dock).
- Problem balloons (#23): `ProblemNotices` (pure) decides which balloon to pop when a problem *starts* (AX > Dock > shortcuts off; "다시 보지 않기" mutes the last) and whether the title gets the warning mark. `MenuBar/ProblemBalloon` is a custom borderless panel on all Spaces under the status item (not `NSPopover`: macOS closes popovers on Space changes, and a `.transient` one of an inactive agent app closes instantly); it stays until its X or a fix button is clicked, and is shown only after Spaces settle (≥1.5 s after detection, 1 s after the last Space change) so it anchors to a still menu bar.
- `Settings/` is a plain `NSWindow`, not the SwiftUI `Settings` scene. Tabs: General, Shortcut (the recorder suspends the tap), Desktops, Permissions.
- `App/AppDelegate` assembles everything. It skips the tap and onboarding when hosting unit tests.

## Rules

- Pure logic (state machine, parsers, planners, `KeyMapper`, `NameStore`, `MRUTracker`, `Shortcut`) must not import AppKit. **Write its tests first.**
- `project.yml` is the source of truth. Private API declarations stay in `Spaces/CGSPrivate.swift` only.
- Don't add external dependencies unless truly needed (SPM only). Keep App Sandbox off.
- Keep signing with `SpaceSwitcher Signing`. Changing the identity forces every user to re-grant Accessibility.
- After changing permissions, hotkeys, Spaces, or UI:
  1. Run `scripts/smoke.swift` if it applies.
  2. Give the user the relevant `docs/MANUAL_TESTS.md` items.
  3. For a bug fix, add a regression item there.
