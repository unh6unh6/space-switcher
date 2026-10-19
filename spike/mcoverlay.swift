// Spike for "names over Mission Control": does a .stationary panel draw above Mission Control,
// and how do WindowManager's windows (the Spaces bar) change while it opens / expands / closes?
// Build: swiftc -O spike/mcoverlay.swift -o build/mcoverlay && ./build/mcoverlay   (runs 40 s)
import AppKit

setvbuf(stdout, nil, _IONBF, 0)
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
@_silgen_name("_CGSDefaultConnection") func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray
let displays = CGSCopyManagedDisplaySpaces(_CGSDefaultConnection()) as! [[String: Any]]
for d in displays {
    let types = (d["Spaces"] as? [[String: Any]] ?? []).map { ($0["type"] as? Int) ?? -1 }
    print("디스플레이: Space \(types.count)개 (데스크탑 \(types.filter { $0 == 0 }.count), 전체 화면 \(types.filter { $0 == 4 }.count)) 순서 \(types)")
}

// Thumbnails of the expanded Spaces bar (layer 15), by window id: max count seen and their resting x.
var thumbs: [Int: String] = [:]
func trackThumbnails() {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    for w in list where (w[kCGWindowOwnerName as String] as? String) == "WindowManager" && (w[kCGWindowLayer as String] as? Int) == 15 {
        let b = w[kCGWindowBounds as String] as! [String: Any]
        if (b["Y"] as? Double ?? 0) == 37 { thumbs[w[kCGWindowNumber as String] as! Int] = "x=\(b["X"]!) \(b["Width"]!)x\(b["Height"]!)" }
    }
}
var last: [String] = []
let start = Date()
print("40초 동안 기록합니다. Mission Control 열기 → 화면 위쪽에 마우스 올려 데스크탑 줄 펼치기 → 닫기")
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    let now = windowManager()
    if now != last, ProcessInfo.processInfo.environment["VERBOSE"] != nil {
        print(String(format: "%5.1fs", Date().timeIntervalSince(start)), now.isEmpty ? "(WindowManager 창 없음)" : now.joined(separator: " | "))
        last = now
    }
    trackThumbnails()
    if Date().timeIntervalSince(start) > 40 {
        print("== 펼친 줄의 썸네일 창 \(thumbs.count)개:"); thumbs.sorted { $0.key < $1.key }.forEach { print("  id=\($0.key) \($0.value)") }
        exit(0)
    }
}
app.run()
