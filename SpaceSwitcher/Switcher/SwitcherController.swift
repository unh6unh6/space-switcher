import AppKit
import SwiftUI

/// Wires the event tap, state machine, panel and stores together.
///
/// Keys in Sticky stay on the event tap rather than making the panel the key window:
/// becoming key requires activating the app, which steals focus from the user's app and
/// can pull macOS onto another Space. Only inline rename activates, because a text field needs it.
///
/// Threading (#10): the event tap runs on its own thread. Everything under "tap thread" is only touched
/// there (via `tap.perform` from elsewhere); everything under "main thread" is UI. Actions cross over with
/// a snapshot of the desktop list, so the two sides never share mutable state.
final class SwitcherController {
    // MARK: tap thread
    private var machine: SwitcherStateMachine!
    private var mru = MRUTracker()
    /// Follows Settings immediately via `Shortcut.didChange` (SPEC §3.6).
    private var shortcut = Shortcut.stored()
    private var suspended = false
    /// Desktops read when the panel opened, as seen by the machine.
    private var tapSpaces: [Space] = []

    // MARK: main thread
    private let names: NameStore
    private let memos: MemoStore
    private let tap = EventTap()
    private let model = SwitcherViewModel()
    private lazy var panel = SwitcherPanel(model: model)
    /// Desktops shown in the panel; rows index into this.
    private var spaces: [Space] = []
    private var clickMonitor: Any?
    /// The desktop being D-edited, what its file holds, and the pending autosave (#27).
    private var memoSpace: Space?
    private var memoSync = MemoSync(loaded: nil)
    private var pendingMemoSave: DispatchWorkItem?
    private let focus = FocusReturner()

    init(names: NameStore, memos: MemoStore) {
        self.names = names
        self.memos = memos
        machine = SwitcherStateMachine { [unowned self] in
            tapSpaces = SpaceProvider.spaces()
            return (count: tapSpaces.count, initial: mru.initialSelection(InitialSelection.stored, in: tapSpaces))
        }

        tap.onKeyDown = { [weak self] key in self?.handleKey(key) ?? false }
        tap.onFlagsChanged = { [weak self] previous, current in
            guard let self, !suspended, KeyMapper.modifierReleased(previous: previous, current: current, shortcut: shortcut)
            else { return }
            send(.modifierReleased)
        }

        model.onClick = { [weak self] row in self?.sendFromMain(.select(row)) }
        model.onDoubleClick = { [weak self] row in
            self?.sendFromMain(.highlight(row))
            self?.sendFromMain(.beginRename)
        }
        model.onCommitRename = { [weak self] text in self?.commitRename(text) }
        model.onCancelRename = { [weak self] in self?.sendFromMain(.endRename) }
        model.onMemoChange = { [weak self] text in self?.memoChanged(text) }
        model.onMemoDone = { [weak self] in self?.finishMemo() }
        model.onToggleTask = { [weak self] line in self?.toggleTask(line) }

        recordCurrentSpace()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.recordCurrentSpace()
        }
        // If the app gets hidden (e.g. Cmd+H while renaming), the panel goes with it; resync the machine
        // or the tap keeps swallowing keys for an invisible panel (#7).
        NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sendFromMain(.dismissed)
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tap.ensureEnabled()
        }
        NotificationCenter.default.addObserver(forName: Shortcut.didChange, object: nil, queue: .main) { [weak self] _ in
            let shortcut = Shortcut.stored()
            self?.tap.perform { self?.shortcut = shortcut }
        }
    }

    /// While the Settings recorder listens, every key must reach it, including the current shortcut.
    func setSuspended(_ value: Bool) {
        tap.perform { [weak self] in self?.suspended = value }
    }

    /// Needs Accessibility; returns false until it is granted.
    @discardableResult
    func start() -> Bool {
        // Build the panel and touch the window list once now, so the first Option+E doesn't pay for it
        // (first open measured 106 ms cold vs ~30 ms warm with app icons on).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            spaces = SpaceProvider.spaces()
            reloadRows()
            panel.layoutIfNeeded()
        }
        return tap.start()
    }

    // MARK: input

    /// Runs inside the tap callback on the tap thread: decide synchronously, render asynchronously.
    private func handleKey(_ key: EventTap.KeyEvent) -> Bool {
        if suspended { return false }
        let decision = KeyMapper.map(keyCode: key.keyCode, flags: key.flags, isAutorepeat: key.isAutorepeat,
                                     shortcut: shortcut, capturing: machine.isCapturingKeys)
        switch decision {
        case .pass:
            return false
        case .consume(let event):
            if let event { send(event) }
            return true
        }
    }

    /// Tap thread only.
    private func send(_ event: SwitcherStateMachine.Event) {
        guard let action = machine.handle(event) else { return }
        let snapshot = tapSpaces
        DispatchQueue.main.async { [weak self] in self?.perform(action, spaces: snapshot) }
    }

    private func sendFromMain(_ event: SwitcherStateMachine.Event) {
        tap.perform { [weak self] in self?.send(event) }
    }

    // MARK: output (main thread)

    private func perform(_ action: SwitcherStateMachine.Action, spaces snapshot: [Space]) {
        switch action {
        case .show(let selection):
            spaces = snapshot
            reloadRows()
            if !snapshot.isEmpty { model.pruneMemoScroll(keeping: Set(snapshot.map(\.id))) }
            model.selection = selection
            model.renamingRow = nil
            model.editingMemoRow = nil
            panel.present()
            startClickMonitor()
        case .select(let row):
            if model.renamingRow != nil || model.editingMemoRow != nil { finishEditUI() }
            model.selection = row
        case .hide:
            close()
        case .switchTo(let row):
            let target = snapshot.indices.contains(row) ? snapshot[row] : nil
            close { if let target { SpaceSwitcherService.switchTo(target) } }
        case .rename(let row):
            guard spaces.indices.contains(row) else { return }
            model.selection = row
            model.draft = names.name(for: spaces[row].id) ?? ""
            model.renamingRow = row
            takeKeyboard()
        case .describe(let row):
            guard spaces.indices.contains(row) else { return }
            model.selection = row
            let space = spaces[row]
            if MemoSettings.load().isLocked(space.id) {   // read-only memo (#27)
                NSSound.beep()
                sendFromMain(.endDescribe)
                return
            }
            let memo = memos.memo(for: space.id)
            memoSpace = space
            memoSync = MemoSync(loaded: memo)
            model.memoEditText = memo ?? ""
            model.memoEditVersion = (memo ?? "").hashValue
            model.editingMemoRow = row
            model.memoFocusRequest += 1
            takeKeyboard()
            panel.recenter()
        case .scrollMemo(let step):
            withAnimation(.easeOut(duration: 0.12)) { model.scrollMemo(by: step) }
        }
    }

    private func takeKeyboard() {
        focus.take(for: panel)
    }

    /// Checkbox click in the preview (#19): flip that line of the selected desktop's memo file.
    private func toggleTask(_ line: Int) {
        guard spaces.indices.contains(model.selection) else { return }
        let space = spaces[model.selection]
        guard !MemoSettings.load().isLocked(space.id), let memo = memos.memo(for: space.id) else { return }
        memos.setMemo(MarkdownBlocks.toggleTask(in: memo, line: line), for: space.id, desktopName: names.displayName(for: space))
        reloadRows()
    }

    // MARK: memo editing (#27): saved as you type, Esc / ⌘Enter / leaving ends it

    private func memoChanged(_ text: String) {
        model.memoEditText = text
        pendingMemoSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushMemo() }
        pendingMemoSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MemoOverlayController.saveDelay, execute: work)
    }

    /// Writes unsaved typing to the edited desktop's file now. Also called when the app quits.
    func flushMemo() {
        pendingMemoSave?.cancel()
        pendingMemoSave = nil
        guard let space = memoSpace, model.editingMemoRow != nil, memoSync.needsSave(model.memoEditText) else { return }
        memoSync.didSave(model.memoEditText)
        memos.setMemo(model.memoEditText, for: space.id, desktopName: names.displayName(for: space))
    }

    private func finishMemo() {
        flushMemo()
        reloadRows()
        sendFromMain(.endDescribe)
    }

    private func commitRename(_ text: String) {
        guard let row = model.renamingRow, spaces.indices.contains(row) else { return }
        names.setName(text, for: spaces[row].id)
        reloadRows()
        sendFromMain(.endRename)
    }

    /// Save and cancel of both inline editors land here; the panel stays open in Sticky (#7, #17).
    private func finishEditUI() {
        flushMemo()
        reloadRows()
        model.renamingRow = nil
        model.editingMemoRow = nil
        returnFocus()
        panel.recenter()
    }

    /// `then` runs once the panel is really off screen, so a following Space switch doesn't animate it (#8).
    private func close(then: @escaping () -> Void = {}) {
        flushMemo()
        model.renamingRow = nil
        model.editingMemoRow = nil
        stopClickMonitor()
        returnFocus()
        panel.hide(then: then)
    }

    private func returnFocus() {
        focus.giveBack()
    }

    /// Icons per desktop (#14); 5 icons per row keeps the 16-row panel compact.
    private static let iconLimit = 5

    private func reloadRows() {
        let lockedMemos = MemoSettings.load().locked
        model.memoDirectory = memos.directory
        let appsBySpace = SpaceApps.showIcons() ? SpaceAppsProvider.current() : nil
        model.rows = spaces.map { space in
            var row = SwitcherViewModel.Row(id: space.id, number: space.index, title: names.displayName(for: space),
                                            isNamed: names.name(for: space.id) != nil, isCurrent: space.isCurrent)
            row.memo = memos.memo(for: space.id)
            row.isLocked = lockedMemos.contains(space.id)
            if let appsBySpace {
                let shown = SpaceApps.visible(appsBySpace[space.managedID] ?? [], limit: Self.iconLimit)
                row.apps = shown.apps
                row.overflow = shown.overflow
            }
            return row
        }
        model.showsMemoPreview = MemoSettings.load().previewEnabled && memos.hasAnyMemo(among: Set(spaces.map(\.id)))
    }

    private func recordCurrentSpace() {
        guard let current = SpaceProvider.spaces().first(where: \.isCurrent) else { return }
        tap.perform { [weak self] in self?.mru.visit(current.id) }
    }

    // Global monitors only see events aimed at other apps, i.e. clicks outside the panel.
    private func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.sendFromMain(.clickOutside)
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}
