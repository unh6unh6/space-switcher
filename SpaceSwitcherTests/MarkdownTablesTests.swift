import XCTest
@testable import SpaceSwitcher

/// #21: pipe tables found in a memo's source.
final class MarkdownTablesTests: XCTestCase {
    private let table = """
    앞 문단
    | 항목 | 상태 | 수 |
    |:-----|:----:|---:|
    | 결제 | **완료** | 3 |
    | 배포 | 대기 |
    뒤 문단
    """

    func testFindsTheTable() {
        let tables = MarkdownTables.find(in: table)
        XCTAssertEqual(tables.count, 1)
        let t = tables[0]
        XCTAssertEqual(t.lines, 1...4)
        XCTAssertEqual(t.header.map(\.text), ["항목", "상태", "수"])
        XCTAssertEqual(t.alignments, [.left, .center, .right])
        XCTAssertEqual(t.rows.map { $0.map(\.text) }, [["결제", "**완료**", "3"], ["배포", "대기", ""]])  // short rows padded
        XCTAssertEqual((table as NSString).substring(with: t.header[0].range), "항목")
    }

    func testPipesWithoutOuterBarsAndEscapes() {
        let t = MarkdownTables.find(in: "a | b\n--- | ---\n1 \\| 2 | 3")[0]
        XCTAssertEqual(t.header.map(\.text), ["a", "b"])
        XCTAssertEqual(t.rows[0].map(\.text), ["1 \\| 2", "3"])
    }

    func testNotATable() {
        XCTAssertTrue(MarkdownTables.find(in: "a | b\n그냥 줄").isEmpty)              // no delimiter row
        XCTAssertTrue(MarkdownTables.find(in: "| a | b |\n|---|").isEmpty)            // column count differs
        XCTAssertTrue(MarkdownTables.find(in: "```\n| a |\n|---|\n```").isEmpty)      // inside a code block
    }

    func testTableEndsAtAPipelessLine() {
        let t = MarkdownTables.find(in: "|a|\n|-|\n|1|\n\n|2|")[0]
        XCTAssertEqual(t.lines, 0...2)
    }

    // MARK: inline text shown in a cell

    func testInlineDisplayDropsMarkers() {
        let shown = MarkdownLiveStyle.displayInline("**완료** 및 `x`")
        XCTAssertEqual(shown.text, "완료 및 x")
        XCTAssertEqual(shown.runs.map { (shown.text as NSString).substring(with: $0.range) }, ["완료", "x"])
        XCTAssertEqual(shown.runs.map(\.kind), [.bold, .code])
    }

    // MARK: caret inside a table shows the whole table

    func testRevealExpandsToWholeTable() {
        XCTAssertEqual(MarkdownLiveStyle.expand(2...2, in: table), 1...4)
        XCTAssertEqual(MarkdownLiveStyle.expand(0...0, in: table), 0...0)
        XCTAssertEqual(MarkdownLiveStyle.expand(0...1, in: table), 0...4)
    }

    // Table lines get a .table run per line plus .syntax for the pipes and the delimiter row.
    func testRunsForTableLines() {
        let runs = MarkdownLiveStyle.runs(in: "|a|b|\n|-|-|\n|1|2|")
        XCTAssertEqual(runs.filter { $0.kind == .table }.map(\.line), [0, 1, 2])
        XCTAssertFalse(runs.contains { $0.kind == .bold || $0.kind == .bullet })
        let pipes = runs.filter { $0.kind == .syntax && $0.line == 0 }.count
        XCTAssertEqual(pipes, 3)
    }
}
