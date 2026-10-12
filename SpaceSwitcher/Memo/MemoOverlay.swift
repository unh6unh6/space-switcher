import AppKit
import SwiftUI

/// The always-on-top memo for the current desktop (#18). One panel on every Space; its content
/// follows the active desktop. Always editable (#27): a click puts the caret in (borrowing the
/// keyboard), typing is saved to the memo file as you go, Esc or a click elsewhere gives it back.
final class MemoOverlayController: NSObject, NSWindowDelegate {
    private let names: NameStore
    private let memos: MemoStore
    private let model = MemoOverlayModel()
    private lazy var panel = MemoOverlayPanel(model: model, delegate: self)
    private let focus = FocusReturner()
    private var settings = MemoSettings.load()
    private var currentSpace: Space?
    /// The desktop whose memo the editor holds, and where its typing is saved.
    private var shownSpace: Space?
    private var sync = MemoSync(loaded: nil)
    private var pendingSave: DispatchWorkItem?
    /// Reading position per desktop (#25), in source lines.
    private var scroll = MemoScrollMemory(persistingAs: "memoScrollOverlay")
    /// Frame changes we make ourselves must not be saved back as "the user moved it".
    private var applyingFrame = false
    /// The desktop whose layout the panel currently shows (#24); nil = shared layout (fullscreen Space).
    private var placedFor: String?? = .none

    static let saveDelay: TimeInterval = 0.5

    init(names: NameStore, memos: MemoStore) {
        self.names = names
        self.memos = memos
        super.init()
        model.onTextChange = { [weak self] text in self?.textChanged(text) }
        model.onWantsFocus = { [weak self] in self?.takeFocus() }
        model.onFocusChange = { [weak self] focused in self?.focusChanged(focused) }
        model.onDone = { [weak self] in self?.endFocus(returnToPreviousApp: true) }
        model.onScroll = { [weak self] line in self?.model.scrollLine = line }
        model.onToggleLock = { [weak self] in self?.toggleLock() }
        model.onToggleCollapse = { [weak self] in self?.toggleCollapse() }
        model.onHover = { [weak self] inside in self?.applyOpacity(hovering: inside) }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        for name in [MemoStore.didChange, NameStore.didChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: MemoSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.settingsChanged()
        }
        // A click in another app takes the keyboard back; stop editing quietly.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, model.isFocused else { return }
            endFocus(returnToPreviousApp: false)
        }
        panel.applyBackground(settings.overlayBackground)
        refresh()
    }

    // MARK: content

    private func refresh() {
        let spaces = SpaceProvider.spaces()
        let current = spaces.first(where: \.isCurrent)
        let moved = current?.id != shownSpace?.id
        if moved {
            // Leaving a desktop mid-typing: its text is saved there, the keyboard goes back.
            flushSave()
            if model.isFocused { endFocus(returnToPreviousApp: false) }
            scroll.set(model.scrollLine, for: shownSpace?.id)
        }
        currentSpace = current
        if !spaces.isEmpty { scroll.prune(keeping: Set(spaces.map(\.id))) }
        model.title = current.map(names.displayName) ?? "전체화면"
        model.canEdit = current != nil
        model.baseDirectory = memos.directory
        model.isLocked = settings.isLocked(current?.id)

        let fileText = current.flatMap { memos.memo(for: $0.id) }
        if moved || shownSpace == nil {
            shownSpace = current
            sync = MemoSync(loaded: fileText)
            show(fileText ?? "", scrollLine: scroll.position(for: current?.id,
                                                            blockCount: MarkdownLiveStyle.lineCount(fileText ?? "")))
        } else {
            shownSpace = current   // fresh name/index
            switch sync.incoming(fileText, editorText: model.text) {
            case .ignore: break
            case .replace:
                sync = MemoSync(loaded: fileText)
                show(fileText ?? "", scrollLine: model.scrollLine)
            case .keepLocal:
                scheduleSave()
            }
        }
        if placedFor != .some(current?.id), panel.isVisible { relocate() }
        updateVisibility()
    }

    private func show(_ text: String, scrollLine: Int) {
        model.text = text
        model.scrollLine = scrollLine
        model.version += 1
    }

    /// New desktop, new layout (#24): fade out, move, fade back in, so the panel doesn't visibly jump
    /// from the previous desktop's spot.
    private func relocate() {
        panel.alphaValue = 0
        placePanel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = settings.opacity
        }
    }

    private func updateVisibility() {
        let empty = model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shouldShow = settings.overlayEnabled && !(settings.hideWhenEmpty && empty && !model.isFocused)
        if shouldShow {
            if !panel.isVisible { placePanel() }
            applyOpacity(hovering: false)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: editing (#27)

    private func textChanged(_ text: String) {
        model.text = text
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// Writes unsaved typing to the shown desktop's file now. Also called when the app quits.
    func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let space = shownSpace, sync.needsSave(model.text) else { return }
        sync.didSave(model.text)
        memos.setMemo(model.text, for: space.id, desktopName: names.displayName(for: space))
    }

    private func takeFocus() {
        guard model.canEdit, !model.isLocked else { return }
        focus.take(for: panel)
    }

    private func focusChanged(_ focused: Bool) {
        model.isFocused = focused
        if !focused { flushSave() }
        applyOpacity(hovering: false)
        updateVisibility()
    }

    /// Esc (back to the app the user was in) or a click elsewhere / desktop change (just let go).
    private func endFocus(returnToPreviousApp: Bool) {
        flushSave()
        panel.makeFirstResponder(nil)
        model.isFocused = false
        if returnToPreviousApp { focus.giveBack() } else { focus.release() }
        applyOpacity(hovering: false)
        updateVisibility()
    }

    private func toggleLock() {
        guard let space = currentSpace else { return }
        if model.isFocused { endFocus(returnToPreviousApp: true) }
        var s = MemoSettings.load()
        s.setLocked(!s.isLocked(space.id), for: space.id)
        s.save()
    }

    // MARK: window

    private func settingsChanged() {
        let oldLayout = settings.layout(for: currentSpace?.id)
        let oldCorner = settings.corner
        settings = MemoSettings.load()
        model.isLocked = settings.isLocked(currentSpace?.id)
        panel.applyBackground(settings.overlayBackground)
        if !applyingFrame, oldCorner != settings.corner || oldLayout != settings.layout(for: currentSpace?.id) {
            placePanel()
        }
        updateVisibility()
    }

    /// Applies the current desktop's layout (#24), falling back to the shared one, then the corner default.
    private func placePanel() {
        guard let screen = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame else { return }
        let layout = settings.layout(for: currentSpace?.id)
        var frame = layout.frame.map { MemoSettings.clamp($0, to: screen) }
            ?? CGRect(origin: settings.corner.origin(for: MemoSettings.defaultSize, in: screen), size: MemoSettings.defaultSize)
        model.isCollapsed = layout.collapsed
        if layout.collapsed {
            // Keep the top edge where it was and shrink to the title bar.
            frame.origin.y = frame.maxY - MemoOverlayPanel.collapsedHeight
            frame.size.height = MemoOverlayPanel.collapsedHeight
        }
        applyingFrame = true
        panel.setFrame(frame, display: true)
        applyingFrame = false
        placedFor = .some(currentSpace?.id)
    }

    /// Collapse/expand this desktop's memo only (#24).
    private func toggleCollapse() {
        if model.isFocused { endFocus(returnToPreviousApp: true) }
        var s = MemoSettings.load()
        var layout = s.layout(for: currentSpace?.id)
        if !layout.collapsed { layout.frame = panel.frame }  // expanding later restores this frame
        layout.collapsed.toggle()
        s.setLayout(layout, for: currentSpace?.id)
        s.save()
    }

    private func applyOpacity(hovering: Bool) {
        panel.alphaValue = (hovering || model.isFocused) ? 1 : settings.opacity
    }

    /// A drag or resize belongs to the desktop on screen (#24).
    private func rememberFrame() {
        guard !applyingFrame else { return }
        var s = MemoSettings.load()
        var layout = s.layout(for: currentSpace?.id)
        guard !layout.collapsed else { return }
        layout.frame = panel.frame
        s.setLayout(layout, for: currentSpace?.id)
        settings = s
        applyingFrame = true
        s.save()
        applyingFrame = false
    }

    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { rememberFrame() }
}

final class MemoOverlayModel: ObservableObject {
    @Published var title = ""
    /// The memo source in the editor. The controller bumps `version` to push a new text in.
    @Published var text = ""
    @Published var version = 0
    @Published var canEdit = true
    @Published var isLocked = false
    @Published var isFocused = false
    @Published var isCollapsed = false
    /// First visible source line (#25).
    @Published var scrollLine = 0
    /// The memo folder, for images (#21).
    @Published var baseDirectory: URL?

    var onTextChange: (String) -> Void = { _ in }
    var onWantsFocus: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var onDone: () -> Void = {}
    var onScroll: (Int) -> Void = { _ in }
    var onToggleLock: () -> Void = {}
    var onToggleCollapse: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
}

/// Titled-but-chromeless panel: free to drag (by its background) and resize, never activates the app
/// by itself, sits above normal and floating windows on every Space, fullscreen apps included.
final class MemoOverlayPanel: NSPanel {
    static let collapsedHeight: CGFloat = 34
    private let effect = NSVisualEffectView()

    func applyBackground(_ background: MemoSettings.Background) {
        PanelBackground.apply(background, to: effect, in: self)
    }

    init(model: MemoOverlayModel, delegate: NSWindowDelegate) {
        super.init(contentRect: CGRect(origin: .zero, size: MemoSettings.defaultSize),
                   styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = CGSize(width: 200, height: Self.collapsedHeight)
        self.delegate = delegate

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: MemoOverlayView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect
    }

    override var canBecomeKey: Bool { true }
}

struct MemoOverlayView: View {
    @ObservedObject var model: MemoOverlayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !model.isCollapsed {
                content
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, model.isCollapsed ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onHover { model.onHover($0) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if model.canEdit {
                Button(action: model.onToggleLock) {
                    Image(systemName: model.isLocked ? "lock.fill" : "lock.open")
                        .foregroundStyle(model.isLocked ? Color.primary : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(model.isLocked ? "읽기 전용 해제" : "읽기 전용으로 잠그기")
            }
            Button(action: model.onToggleCollapse) {
                Image(systemName: model.isCollapsed ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.borderless)
            .help(model.isCollapsed ? "펼치기" : "접기")
        }
        .frame(height: 18)
    }

    private var isEmpty: Bool { model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            LiveMarkdownEditor(text: model.text, version: model.version,
                               editable: model.canEdit && !model.isLocked,
                               canToggleTasks: model.canEdit && !model.isLocked,
                               scrollLine: model.scrollLine,
                               baseDirectory: model.baseDirectory,
                               onTextChange: model.onTextChange,
                               onWantsFocus: model.onWantsFocus,
                               onFocusChange: model.onFocusChange,
                               onDone: model.onDone,
                               onScroll: model.onScroll)
            if isEmpty && !model.isFocused {
                Text(!model.canEdit ? "전체화면 앱에는 메모를 둘 수 없어요" : model.isLocked ? "메모 없음" : "메모 없음 · 클릭해 입력")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
    }
}
