import AppKit
import XCTest
@testable import SpaceSwitcher

/// #27: the live editor really hides markers away from the caret and shows them on it.
/// Set TEST_RUNNER_SNAPSHOT_DIR=<dir> on xcodebuild to also write PNGs for a visual check.
final class LiveMarkdownRenderTests: XCTestCase {
    private let sample = """
    # 오늘
    ## 할 일
    - [ ] **배포** 확인
    - [x] 이슈 정리
    - 그냥 목록 `code` 와 *기울임*
    > 인용문
    ---
    [링크](https://example.com) 끝
    ```
    let x = 1
    ```
    """

    private func makeEditor(_ text: String, width: CGFloat = 320) -> (NSWindow, LiveMarkdownTextView) {
        let view = LiveMarkdownTextView.make()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        view.frame = CGRect(x: 0, y: 0, width: width, height: 360)
        window.contentView = view
        view.setSource(text)
        return (window, view)
    }

    private func lineWidth(_ view: LiveMarkdownTextView, line: Int) -> CGFloat {
        let layout = view.layoutManager!
        layout.ensureLayout(for: view.textContainer!)
        let start = MarkdownLiveStyle.lineStart(line, in: view.string)
        let range = (view.string as NSString).lineRange(for: NSRange(location: start, length: 0))
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: range.length - 1), actualCharacterRange: nil)
        return layout.boundingRect(forGlyphRange: glyphs, in: view.textContainer!).width
    }

    func testMarkersHiddenAwayFromCaretAndShownOnIt() {
        let (window, view) = makeEditor("## 할 일\n본문")
        let hidden = lineWidth(view, line: 0)
        view.isEditable = true
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 1, length: 0))   // caret on the heading line
        let shown = lineWidth(view, line: 0)
        XCTAssertGreaterThan(shown, hidden + 5, "'## ' takes room only on the caret line")
        view.setSelectedRange(NSRange(location: 8, length: 0))   // caret on line 1
        XCTAssertEqual(lineWidth(view, line: 0), hidden, accuracy: 0.5)
        snapshot(view, "caret-line1")
    }

    func testReaderHidesEverything() {
        let (_, view) = makeEditor(sample)
        view.isEditable = false
        view.restyle(force: true)
        XCTAssertEqual(view.string, sample, "the source text itself is never changed")
        snapshot(view, "reader")
    }

    func testBulletOnly() {
        let (_, view) = makeEditor("- 하나\n- 둘\n본문\n> 인용\n끝")
        view.isEditable = false
        view.restyle(force: true)
        snapshot(view, "bullets")
    }

    func testCodeBlockDark() {
        let code = "앞\n```붙여쓴글자\nlet x = 1\n```이것도글자\n```\n뒤"
        for (name, caret) in [("code-reader", nil), ("code-caret-in", 12), ("code-caret-after", (code as NSString).length)] as [(String, Int?)] {
            let (window, view) = makeEditor(code)
            window.appearance = NSAppearance(named: .vibrantDark)
            view.isEditable = caret != nil
            if let caret { window.makeFirstResponder(view); view.setSelectedRange(NSRange(location: caret, length: 0)) }
            view.restyle(force: true)
            snapshot(view, name)
        }
    }

    func testOverlayBackgrounds() {
        final class NoDelegate: NSObject, NSWindowDelegate {}
        let delegate = NoDelegate()
        for background in MemoSettings.Background.allCases where background != .standard {
            let model = MemoOverlayModel()
            model.title = "업무"
            model.text = sample
            model.version = 1
            let panel = MemoOverlayPanel(model: model, delegate: delegate)
            panel.applyBackground(background)
            panel.setFrame(CGRect(x: 0, y: 0, width: 320, height: 300), display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            snapshot(panel.contentView!, "overlay-\(background.rawValue)")
        }
    }

    func testTables() {
        let text = "앞\n| 항목 | 상태 | 수 |\n|:--|:-:|--:|\n| 결제 | **완료** | 3 |\n| 아주 긴 설명이 들어가서 칸 안에서 줄바꿈이 되어야 하는 내용 | 대기 | 12 |\n뒤"
        let (window, view) = makeEditor(text, width: 300)
        window.appearance = NSAppearance(named: .vibrantDark)
        view.isEditable = false
        view.restyle(force: true)
        view.fitHeight()
        snapshot(view, "table-reader")
        let layout = view.layoutManager!
        let firstNewline = (text as NSString).range(of: "\n", range: NSRange(location: 2, length: (text as NSString).length - 2)).location
        let firstLine = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: firstNewline), effectiveRange: nil)
        let drawing = view.textStorage!.attribute(.liveDrawing, at: firstNewline, effectiveRange: nil) as? LiveDrawing
        XCTAssertLessThanOrEqual(drawing?.size.width ?? 999, 300, "the table fits the width")
        XCTAssertGreaterThan(firstLine.height, 60, "the table's first line holds the drawn table")
        view.isEditable = true
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: MarkdownLiveStyle.lineStart(3, in: text) + 3, length: 0))
        snapshot(view, "table-caret")
        let raw = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: firstNewline), effectiveRange: nil)
        XCTAssertLessThan(raw.height, 30, "caret inside: the source shows as plain lines")
    }

    private func makeFolderWithImage() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("memo-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
        let image = NSImage(size: CGSize(width: 400, height: 200), flipped: false) { rect in
            NSColor.systemTeal.setFill(); rect.fill()
            NSColor.white.setFill(); CGRect(x: 20, y: 20, width: 120, height: 60).fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("images/test.png"))
        return folder
    }

    func testImages() throws {
        let folder = try makeFolderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "앞\n![도식](images/test.png)\n![](images/없음.png)\n뒤"
        let (window, view) = makeEditor(text, width: 300)
        view.baseURL = folder
        view.isEditable = false
        view.restyle(force: true)
        view.fitHeight()
        snapshot(view, "image-reader")
        let layout = view.layoutManager!
        let line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 3), effectiveRange: nil)
        XCTAssertEqual(line.height, 154, accuracy: 1, "400×200 fits 300 wide → 300×150, plus 4 paragraph spacing")
        let missing = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: MarkdownLiveStyle.lineStart(2, in: text) + 2), effectiveRange: nil)
        XCTAssertLessThan(missing.height, 30, "a missing image keeps its source line")
        view.isEditable = true
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 4, length: 0))
        let raw = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 3), effectiveRange: nil)
        XCTAssertLessThan(raw.height, 30, "caret on it: the source")
    }

    func testDroppedImageIsCopiedAndLinked() throws {
        let folder = try makeFolderWithImage()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("도식 \(UUID().uuidString.prefix(4)).png")
        try FileManager.default.copyItem(at: folder.appendingPathComponent("images/test.png"), to: outside)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: outside) }
        let (_, view) = makeEditor("앞뒤", width: 300)
        view.baseURL = folder
        view.isEditable = true
        view.insertImageFiles([outside], at: 1)
        XCTAssertEqual(view.string, "앞\n![](<images/\(outside.lastPathComponent)>)\n뒤")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("images/\(outside.lastPathComponent)").path))
        view.insertImageFiles([folder.appendingPathComponent("images/test.png")], at: (view.string as NSString).length)
        XCTAssertTrue(view.string.hasSuffix("뒤\n![](images/test.png)"), "a file already in the memo folder is linked, not copied")
        view.undoManager?.undo()
        XCTAssertFalse(view.string.contains("test.png"))
    }

    func testCaretOnTaskLineShowsItsSource() {
        let (window, view) = makeEditor(sample)
        view.isEditable = true
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: MarkdownLiveStyle.lineStart(2, in: sample) + 3, length: 0))
        snapshot(view, "caret-task")
    }

    private func snapshot(_ view: NSView, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        rep.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = context
        NSColor.gray.setFill()   // stands in for whatever is behind a translucent panel
        view.bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
