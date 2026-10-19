// Spike for "names over Mission Control": does a .stationary panel draw above Mission Control,
// and how do WindowManager's windows (the Spaces bar) change while it opens / expands / closes?
// Build: swiftc -O spike/mcoverlay.swift -o build/mcoverlay && ./build/mcoverlay   (runs 40 s)
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!.frame

func label(_ text: String, at point: NSPoint, level: Int) -> NSPanel {
    let p = NSPanel(contentRect: NSRect(x: point.x, y: point.y, width: 220, height: 34),
                    styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    p.level = NSWindow.Level(rawValue: level)
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    p.ignoresMouseEvents = true
    p.backgroundColor = .systemRed
    let t = NSTextField(labelWithString: text)
    t.frame = NSRect(x: 8, y: 7, width: 210, height: 20); t.textColor = .white; t.font = .boldSystemFont(ofSize: 13)
    p.contentView?.addSubview(t)
    p.orderFrontRegardless()
    return p
}
// One label in the middle of the screen, one inside the Spaces bar (top 96 pt).
let panels = [
    label("A: 화면 가운데 (level 101)", at: NSPoint(x: screen.midX - 110, y: screen.midY), level: 101),
    label("B: 데스크탑 줄 안 (level 101)", at: NSPoint(x: screen.midX - 110, y: screen.maxY - 70), level: 101),
]
_ = panels

func windowManager() -> [String] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    return list.filter { ($0[kCGWindowOwnerName as String] as? String) == "WindowManager" }.map {
        let b = $0[kCGWindowBounds as String] as! [String: Any]
        return "layer=\($0[kCGWindowLayer as String]!) \(b["X"]!),\(b["Y"]!) \(b["Width"]!)x\(b["Height"]!)"
    }.sorted()
}
var last: [String] = []
let start = Date()
print("40초 동안 기록합니다. Mission Control 열기 → 화면 위쪽에 마우스 올려 데스크탑 줄 펼치기 → 닫기")
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    let now = windowManager()
    if now != last {
        print(String(format: "%5.1fs", Date().timeIntervalSince(start)), now.isEmpty ? "(WindowManager 창 없음)" : now.joined(separator: " | "))
        last = now
    }
    if Date().timeIntervalSince(start) > 40 { exit(0) }
}
app.run()
