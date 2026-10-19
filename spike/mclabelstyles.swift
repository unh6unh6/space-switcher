// Spike for #40: name-tag styles side by side over the wallpaper, each on top of a fake macOS
// "데스크탑 N" caption so you can see whether it hides it. Runs 40 s.
// Build: swiftc -O spike/mclabelstyles.swift -o build/mclabelstyles && ./build/mclabelstyles
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!.frame
let size = NSSize(width: 150, height: 22)

func panel(_ frame: NSRect, level: NSWindow.Level) -> NSPanel {
    let p = NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    p.level = level; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
    p.collectionBehavior = [.canJoinAllSpaces, .stationary]
    return p
}
func text(_ s: String, color: NSColor, weight: NSFont.Weight = .medium, shadow: Bool = true) -> NSTextField {
    let t = NSTextField(labelWithString: s)
    t.font = .systemFont(ofSize: 12, weight: weight); t.textColor = color; t.alignment = .center
    if shadow { let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.shadowOffset = NSSize(width: 0, height: -1); sh.shadowBlurRadius = 2; t.shadow = sh }
    return t
}
func center(_ t: NSTextField, in v: NSView) {
    t.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(t)
    NSLayoutConstraint.activate([t.centerXAnchor.constraint(equalTo: v.centerXAnchor), t.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
}
func blur(_ material: NSVisualEffectView.Material, _ appearance: NSAppearance.Name) -> NSVisualEffectView {
    let b = NSVisualEffectView(); b.material = material; b.appearance = NSAppearance(named: appearance)
    b.blendingMode = .behindWindow; b.state = .active; b.wantsLayer = true
    b.layer?.cornerRadius = size.height / 2; b.layer?.masksToBounds = true
    return b
}

typealias Style = (name: String, make: () -> NSView)
let styles: [Style] = [
    ("A 시스템 회색", {
        let b = blur(.hudWindow, .vibrantDark)
        let film = CALayer(); film.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        film.frame = NSRect(origin: .zero, size: size); b.layer?.addSublayer(film)
        center(text("업무 · 회의", color: .white, weight: .regular), in: b); return b }),
    ("B 어두운 반투명", {
        let b = blur(.hudWindow, .vibrantDark)
        center(text("업무 · 회의", color: .white), in: b); return b }),
    ("C 밝은 반투명", {
        let b = blur(.popover, .aqua)
        center(text("업무 · 회의", color: .labelColor, weight: .semibold, shadow: false), in: b); return b }),
    ("D 파란 강조", {
        let v = NSView(); v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        v.layer?.cornerRadius = size.height / 2
        center(text("업무 · 회의", color: .white, weight: .semibold), in: v); return v }),
    ("E 글자만 (그림자)", {
        let b = blur(.hudWindow, .vibrantDark); b.alphaValue = 0.9
        let t = text("업무 · 회의", color: .white, weight: .semibold); center(t, in: b); return b }),
]
var keep: [NSPanel] = []
let gap: CGFloat = 40
let total = CGFloat(styles.count) * size.width + CGFloat(styles.count - 1) * gap
for (i, style) in styles.enumerated() {
    let x = screen.midX - total / 2 + CGFloat(i) * (size.width + gap)
    let y = screen.midY
    // Fake macOS caption pill underneath.
    let under = panel(NSRect(x: x + 20, y: y, width: size.width - 40, height: size.height), level: .floating)
    let pill = NSView(); pill.wantsLayer = true
    pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor; pill.layer?.cornerRadius = size.height / 2
    center(text("데스크탑 \(i + 2)", color: .white, weight: .regular, shadow: false), in: pill)
    under.contentView = pill; under.orderFrontRegardless(); keep.append(under)
    // The style on top.
    let top = panel(NSRect(x: x, y: y, width: size.width, height: size.height), level: .popUpMenu)
    top.contentView = style.make(); top.orderFrontRegardless(); keep.append(top)
    // Caption.
    let cap = panel(NSRect(x: x - 10, y: y - 34, width: size.width + 20, height: 22), level: .popUpMenu)
    let c = NSView(); center(text(style.name, color: .white, weight: .bold), in: c); cap.contentView = c
    cap.orderFrontRegardless(); keep.append(cap)
}
print("화면 가운데에 이름표 후보 5개가 40초 동안 보입니다.")
DispatchQueue.main.asyncAfter(deadline: .now() + 40) { exit(0) }
app.run()
