import XCTest
@testable import SpaceSwitcher

/// #36: a desktop's first memo starts from the template.
final class MemoTemplateTests: XCTestCase {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    /// 2026-10-19 23:30 in Seoul (14:30 UTC).
    private let date = Date(timeIntervalSince1970: 1_792_420_200)

    func testFillsNameAndDate() {
        let out = MemoTemplate.render("# {{name}}\n만든 날: {{date}}\n{{name}}", name: "업무", date: date, timeZone: seoul)
        XCTAssertEqual(out, "# 업무\n만든 날: 2026-10-19\n업무")
    }

    func testUnknownPlaceholdersStay() {
        XCTAssertEqual(MemoTemplate.render("{{todo}} {{ name }}", name: "a", date: date, timeZone: seoul), "{{todo}} {{ name }}")
    }

    func testStartsFromTemplateOnlyWithoutAMemo() {
        let t = "## 할 일\n- [ ] "
        XCTAssertEqual(MemoTemplate.start(memo: nil, template: t, name: "a", date: date, timeZone: seoul), t)
        XCTAssertEqual(MemoTemplate.start(memo: "  \n", template: t, name: "a", date: date, timeZone: seoul), t)
        XCTAssertNil(MemoTemplate.start(memo: "이미 있는 메모", template: t, name: "a", date: date, timeZone: seoul))
        XCTAssertNil(MemoTemplate.start(memo: nil, template: " \n ", name: "a", date: date, timeZone: seoul), "an empty template = start blank")
    }
}
