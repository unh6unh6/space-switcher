import Foundation

struct Space: Identifiable, Equatable {
    /// Persistent key for names: the Space `uuid`, or `mainKey` when the uuid is empty.
    let id: String
    /// Runtime-only ID (`ManagedSpaceID`). Reassigned on reboot, so never persist it.
    let managedID: Int
    /// 1-based position among regular desktops — the N in "Desktop N".
    let index: Int
    /// 0-based position among ALL Spaces on the display, fullscreen ones included.
    /// Ctrl+←/→ steps through this order, so the arrow fallback counts with it.
    let position: Int
    let isCurrent: Bool

    static let mainKey = "__main__"
}

/// Turns the raw `CGSCopyManagedDisplaySpaces` output into regular desktops of the main display.
/// Pure so it can be unit-tested without touching the private API.
enum SpaceParser {
    static let desktopType = 0

    static func parse(_ displays: [[String: Any]], activeSpaceID: Int, mainDisplayID: String?) -> [Space] {
        let rawSpaces = spaces(of: displays, mainDisplayID: mainDisplayID)
        var index = 0
        return rawSpaces.enumerated().compactMap { position, raw in
            guard (raw["type"] as? Int) == desktopType,
                  let managedID = raw["ManagedSpaceID"] as? Int else { return nil }
            index += 1
            let uuid = raw["uuid"] as? String ?? ""
            return Space(id: uuid.isEmpty ? Space.mainKey : uuid,
                         managedID: managedID,
                         index: index,
                         position: position,
                         isCurrent: managedID == activeSpaceID)
        }
    }

    /// Position of the active Space among all Spaces (fullscreen included), or nil if it isn't on the main display.
    static func activePosition(_ displays: [[String: Any]], activeSpaceID: Int, mainDisplayID: String?) -> Int? {
        spaces(of: displays, mainDisplayID: mainDisplayID)
            .firstIndex { ($0["ManagedSpaceID"] as? Int) == activeSpaceID }
    }

    /// How many Spaces the main display has, fullscreen ones included (#40: one Mission Control thumbnail each).
    static func count(_ displays: [[String: Any]], mainDisplayID: String?) -> Int {
        spaces(of: displays, mainDisplayID: mainDisplayID).count
    }

    private static func spaces(of displays: [[String: Any]], mainDisplayID: String?) -> [[String: Any]] {
        let display = displays.first { ($0["Display Identifier"] as? String) == mainDisplayID } ?? displays.first
        return display?["Spaces"] as? [[String: Any]] ?? []
    }
}
