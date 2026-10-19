import AppKit

/// Lays desktop names over the thumbnails of Mission Control's expanded Spaces bar (#40), so it is
/// clear which desktop a window is dropped on or which one is dragged. Mission Control posts nothing,
/// so this polls the window list: slowly while it is closed, at animation pace while it is open so the
/// labels follow thumbnails sliding in and being dragged.
final class MissionControlLabelsController {
    private static let idleInterval: TimeInterval = 0.25
    private static let openInterval: TimeInterval = 1.0 / 30

    private let names: NameStore
    private var timer: Timer?
    private var interval: TimeInterval = 0
    private var spaces = SpaceProvider.Snapshot(spaces: [], activePosition: nil, count: 0)
    private var thumbnailCount = 0
    /// Thumbnail window → Space position, then → label (none for fullscreen app Spaces).
    private var matched: [Int: Int] = [:]
    private var labels: [Int: String] = [:]
    private var panels: [MissionControlLabelPanel] = []

    init(names: NameStore) {
        self.names = names
        NotificationCenter.default.addObserver(forName: MissionControlLayout.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySetting()
        }
        applySetting()
    }

    private func applySetting() {
        if MissionControlLayout.isEnabled() {
            if timer == nil { schedule(Self.idleInterval) }
        } else {
            timer?.invalidate()
            timer = nil
            interval = 0
            reset()
        }
    }

    private func schedule(_ interval: TimeInterval) {
        guard interval != self.interval else { return }
        self.interval = interval
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard case .open(let thumbnails) = MissionControlLayout.state(Self.windows(), display: CGDisplayBounds(CGMainDisplayID())) else {
            if interval == Self.openInterval {
                reset()
                schedule(Self.idleInterval)
            }
            return
        }
        if interval != Self.openInterval {
            spaces = SpaceProvider.snapshot()
            schedule(Self.openInterval)
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

    private func show(_ thumbnails: [MissionControlLayout.Thumbnail]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let shown = thumbnails.compactMap { thumbnail in labels[thumbnail.id].map { (thumbnail.frame, $0) } }
        while panels.count < shown.count { panels.append(MissionControlLabelPanel()) }
        for (panel, (frame, text)) in zip(panels, shown) {
            panel.show(text, over: frame, primaryHeight: primaryHeight)
        }
        for panel in panels.dropFirst(shown.count) { panel.orderOut(nil) }
    }

    private func reset() {
        matched = [:]
        labels = [:]
        thumbnailCount = 0
        for panel in panels { panel.orderOut(nil) }
    }

    private static func windows() -> [MissionControlLayout.Window] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerName as String] as? String, owner == MissionControlLayout.owner,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw) else { return nil }
            return MissionControlLayout.Window(id: id, owner: owner, layer: layer, bounds: bounds)
        }
    }
}

/// One click-through name tag. `.stationary` keeps it on screen while Mission Control is open.
final class MissionControlLabelPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        background.layer?.cornerRadius = 6

        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -3),
        ])
        contentView = background
    }

    func show(_ text: String, over thumbnail: CGRect, primaryHeight: CGFloat) {
        if label.stringValue != text { label.stringValue = text }
        let size = contentView!.fittingSize
        let frame = MissionControlLayout.labelFrame(size: size, thumbnail: thumbnail, primaryHeight: primaryHeight)
        if self.frame != frame { setFrame(frame, display: true) }
        if !isVisible { orderFrontRegardless() }
    }
}
