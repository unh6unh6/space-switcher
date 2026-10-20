import AppKit

/// Lays desktop names over the thumbnails of Mission Control's expanded Spaces bar (#40), so it is
/// clear which desktop a window is dropped on or which one is dragged. Mission Control posts nothing,
/// so this polls the window list every 0.25 s while it is closed, and once per screen refresh (a
/// display link) while it is open so the labels keep up with thumbnails sliding in and being dragged.
final class MissionControlLabelsController: NSObject {
    private static let idleInterval: TimeInterval = 0.25

    private let names: NameStore
    private var timer: Timer?
    private var displayLink: CADisplayLink?
    private var spaces = SpaceProvider.Snapshot(spaces: [], activePosition: nil, count: 0)
    private var thumbnailCount = 0
    /// Thumbnail window → Space position, then → label (none for fullscreen app Spaces).
    private var matched: [Int: Int] = [:]
    private var labels: [Int: String] = [:]
    private var panels: [MissionControlLabelPanel] = []
    /// macOS 26 and earlier (#41): the Dock draws Mission Control and its thumbnails come from AX.
    private let ax = MissionControlAX()
    private var captionBelow = false

    init(names: NameStore) {
        self.names = names
        super.init()
        NotificationCenter.default.addObserver(forName: MissionControlLayout.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySetting()
        }
        applySetting()
    }

    private func applySetting() {
        if MissionControlLayout.isEnabled() {
            if timer == nil, displayLink == nil { startIdle() }
        } else {
            stopPolling()
            reset()
        }
    }

    private func startIdle() {
        stopPolling()
        let timer = Timer(timeInterval: Self.idleInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func startFollowing() {
        stopPolling()
        guard let link = (NSScreen.screens.first ?? NSScreen.main)?.displayLink(target: self, selector: #selector(frame)) else { return }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func frame() { tick() }

    private func tick() {
        guard case .open(let thumbnails) = currentState() else {
            if displayLink != nil {
                reset()
                startIdle()
            }
            return
        }
        if displayLink == nil {
            spaces = SpaceProvider.snapshot()
            startFollowing()
        }
        // A desktop added or removed with Mission Control's own + / ×.
        if thumbnails.count != thumbnailCount {
            thumbnailCount = thumbnails.count
            spaces = SpaceProvider.snapshot()
        }
        let next = MissionControlLayout.match(thumbnails, spaceCount: spaces.count, previous: matched)
        if next != matched {
            matched = next
            labels = next.compactMapValues { position in
                spaces.spaces.first { $0.position == position }.map(names.displayName)
            }
        }
        show(thumbnails)
    }

    private func currentState() -> MissionControlLayout.State {
        let windows = Self.windows()
        let display = CGDisplayBounds(CGMainDisplayID())
        let state = MissionControlLayout.state(windows, display: display)
        guard state == .closed, MissionControlLayout.isDockMissionControlOpen(windows) else {
            captionBelow = false
            return state
        }
        captionBelow = true
        let read = ax.read(display: display)
        return MissionControlLayout.dockState(buttons: read.buttons, spacesGroup: read.group, display: display)
    }

    private func show(_ thumbnails: [MissionControlLayout.Thumbnail]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let shown = thumbnails.compactMap { thumbnail in labels[thumbnail.id].map { (thumbnail.frame, $0) } }
        while panels.count < shown.count { panels.append(MissionControlLabelPanel()) }
        for (panel, (frame, text)) in zip(panels, shown) {
            panel.show(text, over: frame, primaryHeight: primaryHeight, captionBelow: captionBelow)
        }
        for panel in panels.dropFirst(shown.count) { panel.orderOut(nil) }
    }

    private func reset() {
        matched = [:]
        labels = [:]
        thumbnailCount = 0
        ax.reset()
        for panel in panels { panel.orderOut(nil) }
    }

    private static func windows() -> [MissionControlLayout.Window] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerName as String] as? String, owner == MissionControlLayout.owner || owner == MissionControlLayout.dockOwner,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw) else { return nil }
            return MissionControlLayout.Window(id: id, owner: owner, layer: layer, bounds: bounds)
        }
    }
}

/// One click-through name tag. `.stationary` keeps it on screen while Mission Control is open.
/// A dark behind-window blur capsule with bold white text (picked from `spike/mclabelstyles.swift`).
/// Liquid Glass made the tags stutter while following thumbnails, so it is not used.
final class MissionControlLabelPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let blur = NSVisualEffectView()

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        blur.material = .hudWindow
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.masksToBounds = true
        blur.alphaValue = 0.9

        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        label.shadow = shadow
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        blur.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: blur.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -3),
        ])
        contentView = blur
    }

    func show(_ text: String, over thumbnail: CGRect, primaryHeight: CGFloat, captionBelow: Bool) {
        if label.stringValue != text { label.stringValue = text }
        let size = blur.fittingSize
        let frame = MissionControlLayout.labelFrame(size: size, thumbnail: thumbnail, primaryHeight: primaryHeight,
                                                    captionBelow: captionBelow)
        if self.frame != frame {
            let resized = self.frame.size != frame.size
            setFrame(frame, display: false)
            if resized { blur.layer?.cornerRadius = frame.height / 2 }  // a capsule, like macOS's caption pill
        }
        if !isVisible { orderFrontRegardless() }
    }
}
