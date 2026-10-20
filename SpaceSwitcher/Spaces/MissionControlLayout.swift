import CoreGraphics
import Foundation

/// Reads Mission Control so desktop names can be laid over its thumbnails (#40). Pure.
/// - macOS 27 draws it in the WindowManager process: a full-screen backdrop (layer 19), the Spaces bar
///   (layer 14), and, once the bar is expanded, one window per Space thumbnail (layer 15).
/// - macOS 26 and earlier (#41) draw it in the Dock: a full-screen layer-18 window while open, with the
///   thumbnails only in the AX tree (`mc.spaces.list` buttons; see `MissionControlAX`).
/// See phase0-findings ("Mission Control 위에 데스크탑 이름") and #41.
enum MissionControlLayout {
    /// One `CGWindowListCopyWindowInfo` entry. Bounds are in CG global coordinates (top-left origin).
    struct Window: Equatable {
        let id: Int
        let owner: String
        let layer: Int
        let bounds: CGRect

        var thumbnail: Thumbnail { Thumbnail(id: id, frame: bounds) }
    }

    struct Thumbnail: Equatable {
        let id: Int
        let frame: CGRect
    }

    enum State: Equatable {
        case closed
        /// Thumbnails of the main display's Spaces bar, left to right; empty while the bar is collapsed.
        case open([Thumbnail])
    }

    static let owner = "WindowManager"
    static let backdropLayer = 19, barLayer = 14, thumbnailLayer = 15
    static let dockOwner = "Dock", dockOpenLayer = 18
    /// Expanded thumbnails are 160x90 on macOS 26; collapsed captions are ~24 pt tall.
    static let minThumbnailHeight: CGFloat = 50
    /// macOS 26 draws its caption under the thumbnail button.
    static let captionGap: CGFloat = 4
    /// Wide enough to cover macOS's own "데스크탑 N" caption under the thumbnail.
    static let labelMinWidth: CGFloat = 110

    /// `display` is the main display in CG coordinates.
    static func state(_ windows: [Window], display: CGRect) -> State {
        let ours = windows.filter { $0.owner == owner }
        guard ours.contains(where: { $0.layer == backdropLayer || $0.layer == barLayer }) else { return .closed }
        let thumbnails = ours
            .filter { $0.layer == thumbnailLayer && $0.bounds.midX >= display.minX && $0.bounds.midX < display.maxX }
            .sorted { $0.bounds.minX < $1.bounds.minX }
            .map(\.thumbnail)
        return .open(thumbnails)
    }

    static func isDockMissionControlOpen(_ windows: [Window]) -> Bool {
        windows.contains { $0.owner == dockOwner && $0.layer == dockOpenLayer }
    }

    /// macOS 26: `buttons` are the `mc.spaces.list` children (AX frames, top-left origin like CG), `spacesGroup`
    /// is `mc.spaces`. Only an expanded bar on `display` gives thumbnails; while closing, the group slides up
    /// above the screen but its buttons keep reporting the expanded frames.
    static func dockState(buttons: [Thumbnail], spacesGroup: CGRect?, display: CGRect) -> State {
        if let spacesGroup, spacesGroup.minY < display.minY - 1 { return .open([]) }
        let thumbnails = buttons
            .filter { $0.frame.height >= minThumbnailHeight && $0.frame.minY >= display.minY
                && $0.frame.midX >= display.minX && $0.frame.midX < display.maxX }
            .sorted { $0.frame.minX < $1.frame.minX }
        return .open(thumbnails)
    }

    /// Which Space position each thumbnail window shows. The first time all `spaceCount` thumbnails
    /// are there, left to right is the Spaces order; after that a window keeps its Space, so a
    /// thumbnail being dragged to reorder keeps its name. Empty = can't tell yet.
    static func match(_ thumbnails: [Thumbnail], spaceCount: Int, previous: [Int: Int]) -> [Int: Int] {
        if !thumbnails.isEmpty, thumbnails.allSatisfy({ previous[$0.id] != nil }) { return previous }
        guard thumbnails.count == spaceCount else { return [:] }
        return Dictionary(uniqueKeysWithValues: thumbnails.enumerated().map { ($1.id, $0) })
    }

    /// A label of `size` over macOS's own "데스크탑 N" caption, in AppKit coordinates (y grows upward from the
    /// primary screen's bottom; `thumbnail` is top-left based). On macOS 27 the caption is the bottom strip of
    /// the thumbnail window; on macOS 26 (`captionBelow`) it sits under the thumbnail.
    static func labelFrame(size: CGSize, thumbnail: CGRect, primaryHeight: CGFloat, captionBelow: Bool = false) -> CGRect {
        let width = min(max(size.width, labelMinWidth), thumbnail.width)
        let top = captionBelow ? thumbnail.maxY + captionGap + size.height : thumbnail.maxY
        return CGRect(x: thumbnail.midX - width / 2, y: primaryHeight - top, width: width, height: size.height)
    }

    // MARK: setting

    private static let enabledKey = "missionControlLabels"
    static let didChange = Notification.Name("MissionControlLayout.didChange")

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: enabledKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
