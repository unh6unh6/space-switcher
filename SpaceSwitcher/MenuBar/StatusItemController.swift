import AppKit
import Combine
import os

/// Menu bar item: shows the current desktop and lists all desktops.
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let names: NameStore
    private let permissions: PermissionMonitor
    private let showPermissions: () -> Void
    private let showSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private let balloon = ProblemBalloon()
    /// A balloon waits until Space switching has settled: the Dock notice (#22) is detected mid-slide, and
    /// showing it then would anchor it to a menu bar that is still animating between Spaces.
    /// activeSpaceDidChange arrives only when a slide *ends*, so also wait a minimum after detection
    /// for the first slide of the fallback to land.
    private var pendingNotice: ProblemNotices.Notice?
    private var noticeSince = Date.distantPast
    private var lastSpaceChange = Date.distantPast
    private static let settleDelay: TimeInterval = 1.0
    private static let minimumDelay: TimeInterval = 1.5
    /// Problems as of the last check; a balloon pops only for problems that started since (#23).
    /// Missing Accessibility at launch is left to the onboarding window.
    private lazy var lastProblems = ProblemState(accessibilityMissing: !permissions.isTrusted)

    init(names: NameStore, permissions: PermissionMonitor,
         showPermissions: @escaping () -> Void, showSettings: @escaping () -> Void) {
        self.names = names
        self.permissions = permissions
        self.showPermissions = showPermissions
        self.showSettings = showSettings
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshTitle()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshTitle),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastSpaceChange = Date()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshTitle), name: NameStore.didChange, object: names)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshTitle), name: MenuBarTitle.Settings.didChange, object: nil)
        // Debounced: the monitor's first background check lands shortly after launch.
        Publishers.CombineLatest3(permissions.$isTrusted, permissions.$desktopsWithoutShortcut, permissions.$dockIgnoresShortcuts)
            .map { ProblemState(accessibilityMissing: !$0, desktopsWithoutShortcut: $1, dockIgnoresShortcuts: $2) }
            .removeDuplicates()
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] state in self?.problemsChanged(state) }
            .store(in: &cancellables)
    }

    private var currentProblems: ProblemState {
        ProblemState(accessibilityMissing: !permissions.isTrusted,
                     desktopsWithoutShortcut: permissions.desktopsWithoutShortcut,
                     dockIgnoresShortcuts: permissions.dockIgnoresShortcuts)
    }

    private static let log = Logger(subsystem: "io.github.unh6unh6.SpaceSwitcher", category: "Problems")

    private func problemsChanged(_ state: ProblemState) {
        let notices = ProblemNotices.new(previous: lastProblems, current: state, shortcutsMuted: ProblemNotices.shortcutsMuted())
        Self.log.info("problems \(String(describing: state), privacy: .public) → notices \(String(describing: notices), privacy: .public)")
        lastProblems = state
        refreshTitle()
        if let notice = notices.first {
            pendingNotice = notice
            noticeSince = Date()
            showPendingNoticeWhenSettled()
        } else if notices.isEmpty, !ProblemNotices.needsWarningMark(state, shortcutsMuted: ProblemNotices.shortcutsMuted()) {
            pendingNotice = nil
            balloon.close()  // the problem went away while its balloon was still open
        }
    }

    private func showPendingNoticeWhenSettled() {
        let wait = max(Self.settleDelay - Date().timeIntervalSince(lastSpaceChange),
                       Self.minimumDelay - Date().timeIntervalSince(noticeSince))
        guard wait <= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.05) { [weak self] in self?.showPendingNoticeWhenSettled() }
            return
        }
        guard let notice = pendingNotice, let button = statusItem.button else { return }
        pendingNotice = nil
        balloon.show(notice, from: button, actions: .init(
            openPermissions: { [weak self] in self?.showPermissions() },
            restartDock: { DockRestart.confirmAndRestart() },
            openKeyboardSettings: { SystemSettings.open(.keyboard) },
            muteShortcuts: { [weak self] in ProblemNotices.setShortcutsMuted(true); self?.refreshTitle() }))
    }

    /// Style and name length come from Settings → General (#15). Long names are cut only here;
    /// menus show the full name (SPEC §3.5).
    @objc private func refreshTitle() {
        let spaces = SpaceProvider.spaces()
        let current = spaces.first(where: \.isCurrent)
        let settings = MenuBarTitle.Settings.load()
        let title = MenuBarTitle.text(style: settings.style, currentIndex: current?.index, desktopCount: spaces.count,
                                      name: current.flatMap { names.name(for: $0.id) }, maxLength: settings.maxLength)
        let warn = ProblemNotices.needsWarningMark(currentProblems, shortcutsMuted: ProblemNotices.shortcutsMuted())
        statusItem.button?.title = warn ? "⚠︎ \(title)" : title
    }

    // Rebuilt on every open because desktop add/remove/reorder has no notification.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let spaces = SpaceProvider.spaces()

        if !permissions.isTrusted {
            menu.addItem(item("⚠︎ 손쉬운 사용 권한 필요 — 설정…", #selector(openPermissions)))
            menu.addItem(.separator())
        }
        if permissions.dockIgnoresShortcuts {
            menu.addItem(item("⚠︎ 데스크탑 전환 단축키 응답 없음 — Dock 다시 시작…", #selector(restartDock)))
            menu.addItem(.separator())
        }
        let off = permissions.desktopsWithoutShortcut
        if !off.isEmpty {
            let numbers = off.map(String.init).joined(separator: ", ")
            menu.addItem(item("⚠︎ 데스크탑 \(numbers)번 전환 단축키 꺼짐 — 시스템 설정…", #selector(openKeyboardSettings)))
            menu.addItem(.separator())
        }
        for space in spaces {
            let entry = item("", #selector(selectSpace(_:)))
            entry.attributedTitle = title(for: space)
            entry.representedObject = space.id
            entry.state = space.isCurrent ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let rename = item("현재 데스크탑 이름 변경…", #selector(renameCurrent))
        rename.isEnabled = spaces.contains(where: \.isCurrent)  // not on fullscreen Spaces
        menu.addItem(rename)
        let memoSettings = MemoSettings.load()
        if memoSettings.enabled {   // the memo feature can be off (#42)
            let memo = item("메모 띄우기", #selector(toggleMemoOverlay))
            memo.state = memoSettings.overlayEnabled ? .on : .off
            menu.addItem(memo)
        }
        let settings = item("설정…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "SpaceSwitcher 종료",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        refreshTitle()
    }

    /// "1  업무", or a dimmed "3  데스크탑 3" when unnamed.
    private func title(for space: Space) -> NSAttributedString {
        let text = "\(space.index)  \(names.displayName(for: space))"
        let named = names.name(for: space.id) != nil
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: named ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ])
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func selectSpace(_ sender: NSMenuItem) {
        // Re-resolve by id: the list may have changed since the menu was built.
        guard let id = sender.representedObject as? String,
              let target = SpaceProvider.spaces().first(where: { $0.id == id }) else { return }
        if !permissions.isTrusted {
            showPermissions()
            return
        }
        SpaceSwitcherService.switchTo(target)
    }

    @objc private func renameCurrent() {
        guard let current = SpaceProvider.spaces().first(where: \.isCurrent),
              let entered = RenamePrompt.run(for: current, currentName: names.name(for: current.id)) else { return }
        names.setName(entered, for: current.id)
    }

    @objc private func openPermissions() {
        showPermissions()
    }

    @objc private func openKeyboardSettings() {
        SystemSettings.open(.keyboard)
    }

    @objc private func restartDock() {
        DockRestart.confirmAndRestart()
    }

    @objc private func toggleMemoOverlay() {
        var settings = MemoSettings.load()
        settings.overlayEnabled.toggle()
        settings.save()
    }

    @objc private func openSettings() {
        showSettings()
    }
}
