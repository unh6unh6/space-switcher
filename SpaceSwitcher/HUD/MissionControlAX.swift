import AppKit
import ApplicationServices

/// macOS 26 and earlier (#41): the Dock draws Mission Control in one full-screen window, so the Spaces
/// bar thumbnails are only visible through the Dock's AX tree:
/// `mc` › `mc.display` › `mc.spaces` › `mc.spaces.list` › one `AXButton` per Space, in Spaces order.
/// (macOS 27 exposes nothing here; it has thumbnail windows instead.) Needs Accessibility, which the
/// app has anyway. Elements are looked up once per Mission Control session and then only their frames
/// are read; each button gets a stable id for `MissionControlLayout.match`.
final class MissionControlAX {
    private var group: AXUIElement?
    private var list: AXUIElement?
    /// Buttons seen this session; the index is the id.
    private var known: [AXUIElement] = []

    func read(display: CGRect) -> (group: CGRect?, buttons: [MissionControlLayout.Thumbnail]) {
        if list == nil { find(display: display) }
        guard let list else { return (nil, []) }
        let buttons = Self.children(of: list).filter { Self.string(of: $0, kAXRoleAttribute) == kAXButtonRole as String }
        return (group.flatMap(Self.frame), buttons.compactMap { button in
            Self.frame(of: button).map { MissionControlLayout.Thumbnail(id: id(of: button), frame: $0) }
        })
    }

    /// Mission Control closed: its elements are rebuilt next time.
    func reset() {
        group = nil
        list = nil
        known = []
    }

    private func id(of element: AXUIElement) -> Int {
        if let index = known.firstIndex(where: { CFEqual($0, element) }) { return index }
        known.append(element)
        return known.count - 1
    }

    /// The `mc.spaces` group of the display whose bar is on `display` (the first one otherwise).
    private func find(display: CGRect) {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let mc = Self.children(of: app).first(where: { Self.identifier($0) == "mc" }) else { return }
        let groups = Self.children(of: mc)
            .filter { Self.identifier($0) == "mc.display" }
            .compactMap { display in Self.children(of: display).first { Self.identifier($0) == "mc.spaces" } }
        let onDisplay = groups.first { group in
            Self.frame(of: group).map { $0.midX >= display.minX && $0.midX < display.maxX } ?? false
        }
        guard let spaces = onDisplay ?? groups.first,
              let list = Self.children(of: spaces).first(where: { Self.identifier($0) == "mc.spaces.list" }) else { return }
        group = spaces
        self.list = list
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func identifier(_ element: AXUIElement) -> String? {
        string(of: element, kAXIdentifierAttribute)
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// AX frames are in global coordinates with a top-left origin, like the window list.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }
}
