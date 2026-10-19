import AppKit
import XCTest
@testable import SpaceSwitcher

/// #29: ⌘←/⌘→ (and their ⇧ forms) stay on the caret's own line even when neighbouring lines hide
/// their leading markers.
final class LiveMarkdownCaretTests: XCTestCase {
    private func editor(_ text: String) -> (NSWindow, LiveMarkdownTextView) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let (scroll, view) = LiveMarkdownEditor.makeScrollView()
        scroll.frame = window.contentView!.bounds
        window.contentView!.addSubview(scroll)
        view.isEditable = true
        view.setSource(text)
        window.makeFirstResponder(view)
        return (window, view)
    }

    private func check(_ text: String, line: Int, column: Int, file: StaticString = #filePath, lineNumber: UInt = #line) {
        let (_, view) = editor(text)
        let start = MarkdownLiveStyle.lineStart(line, in: text)
        let end = (text as NSString).lineRange(for: NSRange(location: start, length: 0)).upperBound
        let lineEnd = end > start && (text as NSString).character(at: end - 1) == 10 ? end - 1 : end
        let caret = start + column

        for selector in [#selector(NSResponder.moveToRightEndOfLine(_:)), #selector(NSResponder.moveToEndOfLine(_:))] {
            view.setSelectedRange(NSRange(location: caret, length: 0))
            view.doCommand(by: selector)
            XCTAssertEqual(view.selectedRange(), NSRange(location: lineEnd, length: 0), "\(selector) on line \(line)", file: file, line: lineNumber)
        }
        for selector in [#selector(NSResponder.moveToLeftEndOfLine(_:)), #selector(NSResponder.moveToBeginningOfLine(_:))] {
            view.setSelectedRange(NSRange(location: caret, length: 0))
            view.doCommand(by: selector)
            XCTAssertEqual(view.selectedRange(), NSRange(location: start, length: 0), "\(selector) on line \(line)", file: file, line: lineNumber)
        }
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.doCommand(by: #selector(NSResponder.moveToRightEndOfLineAndModifySelection(_:)))
        XCTAssertEqual(view.selectedRange(), NSRange(location: caret, length: lineEnd - caret), "⇧⌘→", file: file, line: lineNumber)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.doCommand(by: #selector(NSResponder.moveToLeftEndOfLineAndModifySelection(_:)))
        XCTAssertEqual(view.selectedRange(), NSRange(location: start, length: caret - start), "⇧⌘←", file: file, line: lineNumber)
    }

    func testTaskLines() {
        let text = "- [ ] 첫째\n- [ ] 둘째\n- [ ] 셋째"
        for line in 0...2 { check(text, line: line, column: 7) }
    }

    func testOtherHiddenMarkers() {
        check("- 하나\n- 둘\n- 셋", line: 1, column: 3)
        check("> 인용 하나\n> 인용 둘\n끝", line: 0, column: 3)
        check("## 제목\n## 둘째 제목\n본문", line: 0, column: 4)
        check("본문\n## 제목\n- [ ] 할 일", line: 0, column: 1)
    }

    // #38: the caret bar reaches 1pt left of its spot; at a line start it must not be cut by the clip edge.
    func testLineStartCaretIsNotClipped() {
        let (_, view) = editor("첫 줄\n\n셋째")
        for location in [0, 4, 5] {
            view.setSelectedRange(NSRange(location: location, length: 0))
            let rect = view.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
            let inView = view.convert(view.window!.convertFromScreen(rect), from: nil)
            XCTAssertGreaterThanOrEqual(inView.minX - 1, -0.01, "caret at \(location) keeps its left half")
        }
    }

    // MARK: pure clamp

    func testClampKeepsMovesInsideTheLine() {
        let text = "ab\ncd\nef"
        // Default move landed on another line → pulled back to this line's end / start.
        XCTAssertEqual(MarkdownLiveStyle.clamp(5, from: 4, towardEnd: true, in: text), 5)    // same line: unchanged
        XCTAssertEqual(MarkdownLiveStyle.clamp(7, from: 4, towardEnd: true, in: text), 5)    // into "ef" → end of "cd"
        XCTAssertEqual(MarkdownLiveStyle.clamp(1, from: 4, towardEnd: false, in: text), 3)   // into "ab" → start of "cd"
        XCTAssertEqual(MarkdownLiveStyle.clamp(8, from: 7, towardEnd: true, in: text), 8)    // last line end
    }
}
