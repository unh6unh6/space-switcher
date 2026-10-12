// Spike: where does NSTextInsertionIndicator sit (and how wide) for a plain NSTextView vs. our setup?
//   swift spike/caret.swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let previous = NSWorkspace.shared.frontmostApplication

func indicator(_ v: NSView) -> String {
    func walk(_ v: NSView) -> [NSView] { v.subviews + v.subviews.flatMap(walk) }
    return walk(v).filter { String(describing: type(of: $0)).contains("Insertion") }.map { "\($0.frame.integral)" }.joined()
}

func make(_ name: String, padding: CGFloat?, nonactivating: Bool) -> (NSPanel, NSTextView) {
    let panel = NSPanel(contentRect: CGRect(x: 300, y: 300, width: 300, height: 200),
                        styleMask: nonactivating ? [.titled, .nonactivatingPanel] : [.titled], backing: .buffered, defer: false)
    let tv = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    if let padding { tv.textContainer?.lineFragmentPadding = padding }
    tv.string = "first\n\nthird"
    panel.contentView = tv
    panel.title = name
    return (panel, tv)
}

app.activate(ignoringOtherApps: true)
var results: [String] = []
let cases: [(String, CGFloat?, Bool)] = [("plain", nil, false), ("pad0", 0, false), ("plain-nonact", nil, true), ("pad0-nonact", 0, true)]
var index = 0
func next() {
    guard index < cases.count else {
        results.forEach { print($0) }
        previous?.activate()
        exit(0)
    }
    let (name, padding, nonact) = cases[index]; index += 1
    let (panel, tv) = make(name, padding: padding, nonactivating: nonact)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(tv)
    var out = "\(name):"
    let spots = [0, 3, 6, 7]   // line start, middle, empty line, start of third
    func probe(_ i: Int) {
        guard i < spots.count else { results.append(out); panel.orderOut(nil); next(); return }
        tv.setSelectedRange(NSRange(location: spots[i], length: 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            out += " @\(spots[i])=\(indicator(tv))"
            probe(i + 1)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { probe(0) }
}
DispatchQueue.main.async { next() }
app.run()
