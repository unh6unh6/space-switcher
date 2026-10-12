import AppKit
import XCTest
@testable import SpaceSwitcher

/// #21: the shortcuts reach the editor and are one undo step each.
final class LiveMarkdownShortcutTests: XCTestCase {
    private func editor(_ text: String, caret: Int) -> (NSWindow, LiveMarkdownTextView) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let (scroll, view) = LiveMarkdownEditor.makeScrollView()
        scroll.frame = window.contentView!.bounds
        window.contentView!.addSubview(scroll)
        view.isEditable = true
        view.setSource(text)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        return (window, view)
    }

    private func key(_ code: UInt16, _ chars: String, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    func testCommandLMakesATaskEvenWithKoreanCharacters() {
        let (window, view) = editor("할 일", caret: 3)
        view.keyDown(with: key(37, "ㅣ", in: window))   // ⌘L on a Korean layout reports "ㅣ"
        XCTAssertEqual(view.string, "- [ ] 할 일")
        view.undoManager?.undo()
        XCTAssertEqual(view.string, "할 일")
    }

    func testCommandBWrapsSelection() {
        let (window, view) = editor("a 굵게 b", caret: 0)
        view.setSelectedRange(NSRange(location: 2, length: 2))
        view.keyDown(with: key(11, "ㅠ", in: window))
        XCTAssertEqual(view.string, "a **굵게** b")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: 2))
    }

    func testEnterAndTabInLists() {
        let (_, view) = editor("- 사과", caret: 4)
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "- 사과\n- ")
        view.insertTab(nil)
        XCTAssertEqual(view.string, "- 사과\n  - ")
        view.insertBacktab(nil)
        view.insertNewline(nil)                       // empty item: ends the list
        XCTAssertEqual(view.string, "- 사과\n")
        view.insertNewline(nil)                       // plain newline outside lists
        XCTAssertEqual(view.string, "- 사과\n\n")
    }
}
