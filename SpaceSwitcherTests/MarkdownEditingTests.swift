import XCTest
@testable import SpaceSwitcher

/// #21: editing shortcuts as pure text transforms. `|` marks the caret, `[…]` the selection.
final class MarkdownEditingTests: XCTestCase {
    /// "ab«cd»e" → text "abcde", selection {2, 2}; "ab|c" → caret at 2.
    private func parse(_ marked: String) -> (String, NSRange) {
        let s = marked as NSString
        let open = s.range(of: "«"), caret = s.range(of: "|")
        if open.location != NSNotFound {
            let close = s.range(of: "»")
            let inner = s.substring(with: NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open)))
            let text = s.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
            return (text, NSRange(location: open.location, length: (inner as NSString).length))
        }
        return (s.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
    }

    private func show(_ text: String, _ selection: NSRange) -> String {
        let s = text as NSString
        if selection.length == 0 {
            return s.substring(to: selection.location) + "|" + s.substring(from: selection.location)
        }
        return s.substring(to: selection.location) + "«" + s.substring(with: selection) + "»" + s.substring(from: NSMaxRange(selection))
    }

    private func run(_ marked: String, _ transform: (String, NSRange) -> MarkdownEditing.Replacement?) -> String? {
        let (text, selection) = parse(marked)
        guard let r = transform(text, selection) else { return nil }
        return show((text as NSString).replacingCharacters(in: r.range, with: r.string), r.selection)
    }

    // MARK: wrap (⌘B ⌘I ⌘E)

    func testWrapSelection() {
        XCTAssertEqual(run("a «굵게» b") { MarkdownEditing.toggleWrap("**", text: $0, selection: $1) }, "a **«굵게»** b")
        XCTAssertEqual(run("«x»") { MarkdownEditing.toggleWrap("`", text: $0, selection: $1) }, "`«x»`")
    }

    func testUnwrapSelection() {
        XCTAssertEqual(run("a **«굵게»** b") { MarkdownEditing.toggleWrap("**", text: $0, selection: $1) }, "a «굵게» b")
        XCTAssertEqual(run("a «**굵게**» b") { MarkdownEditing.toggleWrap("**", text: $0, selection: $1) }, "a «굵게» b")
    }

    func testItalicDoesNotEatBold() {
        XCTAssertEqual(run("**«x»**") { MarkdownEditing.toggleWrap("*", text: $0, selection: $1) }, "***«x»***")
        XCTAssertEqual(run("***«x»***") { MarkdownEditing.toggleWrap("*", text: $0, selection: $1) }, "**«x»**")
    }

    func testWrapAtCaretInsertsAPair() {
        XCTAssertEqual(run("ab|") { MarkdownEditing.toggleWrap("**", text: $0, selection: $1) }, "ab**|**")
        XCTAssertEqual(run("ab**|**") { MarkdownEditing.toggleWrap("**", text: $0, selection: $1) }, "ab|")
    }

    // MARK: link (⌘K)

    func testLinkFromSelection() {
        XCTAssertEqual(run("보기 «문서» 끝") { MarkdownEditing.link(text: $0, selection: $1) }, "보기 [문서](«url») 끝")
    }

    func testLinkFromURLSelectionAndCaret() {
        XCTAssertEqual(run("«https://a.b»") { MarkdownEditing.link(text: $0, selection: $1) }, "[|](https://a.b)")
        XCTAssertEqual(run("a|") { MarkdownEditing.link(text: $0, selection: $1) }, "a[|](url)")
    }

    // MARK: task (⌘L)

    func testTaskLine() {
        XCTAssertEqual(run("할 일|") { MarkdownEditing.toggleTask(text: $0, selection: $1) }, "- [ ] 할 일|")
        XCTAssertEqual(run("- 사과|") { MarkdownEditing.toggleTask(text: $0, selection: $1) }, "- [ ] 사과|")
        XCTAssertEqual(run("- [ ] 사|과") { MarkdownEditing.toggleTask(text: $0, selection: $1) }, "- [x] 사|과")
        XCTAssertEqual(run("  - [x] 끝|") { MarkdownEditing.toggleTask(text: $0, selection: $1) }, "  - [ ] 끝|")
        XCTAssertEqual(run("|") { MarkdownEditing.toggleTask(text: $0, selection: $1) }, "- [ ] |")
        XCTAssertEqual(run("a\n|b") { MarkdownEditing.toggleTask(text: $0, selection: $1) }, "a\n- [ ] |b")
    }

    // MARK: Enter in lists

    func testEnterContinuesLists() {
        XCTAssertEqual(run("- 사과|") { MarkdownEditing.newline(text: $0, selection: $1) }, "- 사과\n- |")
        XCTAssertEqual(run("  * 배|") { MarkdownEditing.newline(text: $0, selection: $1) }, "  * 배\n  * |")
        XCTAssertEqual(run("- [x] 됨|") { MarkdownEditing.newline(text: $0, selection: $1) }, "- [x] 됨\n- [ ] |")
        XCTAssertEqual(run("9. 아홉|") { MarkdownEditing.newline(text: $0, selection: $1) }, "9. 아홉\n10. |")
        XCTAssertEqual(run("> 인용|") { MarkdownEditing.newline(text: $0, selection: $1) }, "> 인용\n> |")
    }

    func testEnterSplitsAnItem() {
        XCTAssertEqual(run("- 사|과") { MarkdownEditing.newline(text: $0, selection: $1) }, "- 사\n- |과")
    }

    func testEnterOnEmptyItemEndsTheList() {
        XCTAssertEqual(run("- 사과\n- |") { MarkdownEditing.newline(text: $0, selection: $1) }, "- 사과\n|")
        XCTAssertEqual(run("- [ ] |") { MarkdownEditing.newline(text: $0, selection: $1) }, "|")
    }

    func testEnterOutsideListsIsDefault() {
        XCTAssertNil(run("문장|") { MarkdownEditing.newline(text: $0, selection: $1) })
        XCTAssertNil(run("-|") { MarkdownEditing.newline(text: $0, selection: $1) })
        XCTAssertNil(run("- 사«과»") { MarkdownEditing.newline(text: $0, selection: $1) })
        XCTAssertNil(run("|- 사과") { MarkdownEditing.newline(text: $0, selection: $1) })   // caret before the marker
    }

    // MARK: Tab in lists

    func testTabIndentsListItems() {
        XCTAssertEqual(run("- 사|과") { MarkdownEditing.indent(text: $0, selection: $1, outdent: false) }, "  - 사|과")
        XCTAssertEqual(run("    - 사|과") { MarkdownEditing.indent(text: $0, selection: $1, outdent: true) }, "  - 사|과")
        XCTAssertEqual(run(" - 사|과") { MarkdownEditing.indent(text: $0, selection: $1, outdent: true) }, "- 사|과")
        XCTAssertNil(run("문장|") { MarkdownEditing.indent(text: $0, selection: $1, outdent: false) })
        XCTAssertNil(run("- 맨 앞|") { MarkdownEditing.indent(text: $0, selection: $1, outdent: true) })
    }

    func testTabOverSeveralItems() {
        XCTAssertEqual(run("«- a\n- b»") { MarkdownEditing.indent(text: $0, selection: $1, outdent: false) }, "«  - a\n  - b»")
    }
}
