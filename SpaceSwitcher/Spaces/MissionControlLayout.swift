import CoreGraphics
import Foundation

/// Reads Mission Control from the window list so desktop names can be laid over its thumbnails (#40).
/// macOS 27 draws Mission Control in the WindowManager process: a full-screen backdrop (layer 19), the
/// Spaces bar (layer 14), and, once the bar is expanded, one window per Space thumbnail (layer 15).
/// See phase0-findings ("Mission Control 위에 데스크탑 이름"). Pure.
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
    static let labelInset: CGFloat = 6

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

    /// Which Space position each thumbnail window shows. The first time all `spaceCount` thumbnails
    /// are there, left to right is the Spaces order; after that a window keeps its Space, so a
    /// thumbnail being dragged to reorder keeps its name. Empty = can't tell yet.
    static func match(_ thumbnails: [Thumbnail], spaceCount: Int, previous: [Int: Int]) -> [Int: Int] {
        if !thumbnails.isEmpty, thumbnails.allSatisfy({ previous[$0.id] != nil }) { return previous }
        guard thumbnails.count == spaceCount else { return [:] }
        return Dictionary(uniqueKeysWithValues: thumbnails.enumerated().map { ($1.id, $0) })
    }

    /// A label of `size` at the bottom centre inside `thumbnail`, in AppKit coordinates.
    static func labelFrame(size: CGSize, thumbnail: CGRect, primaryHeight: CGFloat) -> CGRect {
        let width = min(size.width, thumbnail.width - 2 * labelInset)
        return CGRect(x: thumbnail.midX - width / 2,
                      y: primaryHeight - thumbnail.maxY + labelInset,
                      width: width, height: size.height)
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
