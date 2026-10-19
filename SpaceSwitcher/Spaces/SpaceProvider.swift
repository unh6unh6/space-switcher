import ColorSync  // CGDisplayCreateUUIDFromDisplayID
import CoreGraphics
import Foundation

/// Reads the current desktop list. There is no notification for add/remove/reorder,
/// so callers re-query every time a menu or panel opens.
enum SpaceProvider {
    struct Snapshot {
        let spaces: [Space]
        /// Active Space among all Spaces (fullscreen included); nil if not on the main display.
        let activePosition: Int?
        /// All Spaces of the main display, fullscreen included.
        let count: Int
    }

    static func spaces() -> [Space] {
        snapshot().spaces
    }

    static func snapshot() -> Snapshot {
        let cid = CGSMainConnectionID()
        let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] ?? []
        let active = CGSGetActiveSpace(cid)
        let main = mainDisplayUUID()
        return Snapshot(spaces: SpaceParser.parse(displays, activeSpaceID: active, mainDisplayID: main),
                        activePosition: SpaceParser.activePosition(displays, activeSpaceID: active, mainDisplayID: main),
                        count: SpaceParser.count(displays, mainDisplayID: main))
    }

    private static func mainDisplayUUID() -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
