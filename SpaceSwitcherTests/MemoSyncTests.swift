import XCTest
@testable import SpaceSwitcher

/// #27: the editor writes as you type; what to do when the file changes underneath it.
final class MemoSyncTests: XCTestCase {
    func testOwnWriteEchoIsIgnored() {
        var sync = MemoSync(loaded: "a")
        sync.didSave("a\nb\n")
        // The store trims what it writes; the watcher reports that back.
        XCTAssertEqual(sync.incoming("a\nb", editorText: "a\nb\n"), .ignore)
    }

    func testOutsideEditReplacesAnUntouchedEditor() {
        let sync = MemoSync(loaded: "a")
        XCTAssertEqual(sync.incoming("changed in Obsidian", editorText: "a"), .replace)
    }

    // Typing not yet saved wins; it overwrites the file on the next save.
    func testUnsavedTypingWinsOverOutsideEdit() {
        let sync = MemoSync(loaded: "a")
        XCTAssertEqual(sync.incoming("changed in Obsidian", editorText: "a typed"), .keepLocal)
    }

    func testDeletedFileIsEmpty() {
        let sync = MemoSync(loaded: "a")
        XCTAssertEqual(sync.incoming(nil, editorText: "a"), .replace)
        XCTAssertEqual(MemoSync(loaded: nil).incoming(nil, editorText: ""), .ignore)
    }

    func testNeedsSave() {
        var sync = MemoSync(loaded: "a")
        XCTAssertFalse(sync.needsSave("a\n"))        // only whitespace differs
        XCTAssertTrue(sync.needsSave("ab"))
        sync.didSave("ab")
        XCTAssertFalse(sync.needsSave("ab"))
    }

    // #36: an untouched template is not a memo — nothing to save until the user changes it.
    func testUntouchedTemplateIsNotSaved() {
        var sync = MemoSync(loaded: nil)
        sync.startFromTemplate("## 할 일\n- [ ] ")
        XCTAssertFalse(sync.needsSave("## 할 일\n- [ ] "))
        XCTAssertTrue(sync.isUntouchedTemplate("## 할 일\n- [ ] "))
        XCTAssertTrue(sync.needsSave("## 할 일\n- [ ] 배포"))
        XCTAssertFalse(sync.isUntouchedTemplate("## 할 일\n- [ ] 배포"))
    }

    // Once something was saved, going back to the template text is a real edit again.
    func testTemplateCountsOnlyUntilTheFirstSave() {
        var sync = MemoSync(loaded: nil)
        sync.startFromTemplate("T")
        sync.didSave("T plus")
        XCTAssertTrue(sync.needsSave("T"))
        XCTAssertFalse(sync.isUntouchedTemplate("T"))
    }

    // A memo written elsewhere meanwhile replaces an untouched template.
    func testOutsideMemoReplacesUntouchedTemplate() {
        var sync = MemoSync(loaded: nil)
        sync.startFromTemplate("T")
        XCTAssertEqual(sync.incoming("from Obsidian", editorText: "T"), .replace)
    }
}
