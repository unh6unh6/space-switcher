import AppKit
import SwiftUI
import XCTest
@testable import SpaceSwitcher

/// #35: grouped rows get a header each, and the list grows by exactly those headers (empty ones too, #43).
/// Set TEST_RUNNER_SNAPSHOT_DIR=<dir> to also write a PNG for a visual check.
final class SwitcherCategoryRenderTests: XCTestCase {
    private func rows() -> [SwitcherViewModel.Row] {
        ["메일", "배포", "모니터링", "개인"].enumerated().map { i, title in
            SwitcherViewModel.Row(id: "s\(i)", number: [2, 4, 1, 3][i], title: title, isNamed: true, isCurrent: i == 2)
        }
    }

    private static func header(_ title: String, empty: Bool = false) -> SwitcherViewModel.Line {
        .header(title: title, slot: .header(title), isEmpty: empty)
    }

    /// todo: 2 rows · doing: empty · monitoring: 1 row · 미분류: 1 row.
    static let grouped: [SwitcherViewModel.Line] = [header("todo"), .row(0), .row(1), header("doing", empty: true),
                                                    header("monitoring"), .row(2), header("미분류"), .row(3)]

    private func height(grouped: Bool, name: String) -> CGFloat {
        let model = SwitcherViewModel()
        model.rows = rows()
        model.lines = grouped ? Self.grouped : []
        model.canReorder = grouped
        model.selection = 1
        let host = NSHostingView(rootView: SwitcherView(model: model))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        snapshot(host, name)
        return host.fittingSize.height
    }

    func testHeadersAddTheirHeight() {
        let plain = height(grouped: false, name: "switcher-plain")
        let grouped = height(grouped: true, name: "switcher-grouped")
        XCTAssertEqual(grouped - plain, 4 * (SwitcherView.headerHeight + 2), accuracy: 1)
    }

    // #44: where a dragged row lands. Lines: header 0–20, rows 22–52 and 54–84, header 86–106, ...
    func testDropTargetFollowsTheLineUnderThePointer() {
        func target(_ y: CGFloat) -> (Int, Bool)? {
            SwitcherViewModel.dropTarget(at: y, in: Self.grouped, rowHeight: SwitcherView.rowHeight,
                                         headerHeight: SwitcherView.headerHeight, spacing: SwitcherView.spacing).map { ($0.line, $0.after) }
        }
        XCTAssertTrue(target(-10)! == (0, true), "above everything: under the first header")
        XCTAssertTrue(target(30)! == (1, false), "upper half of a row: before it")
        XCTAssertTrue(target(45)! == (1, true), "lower half: after it")
        XCTAssertTrue(target(95)! == (3, true), "an empty header: into that category")
        XCTAssertTrue(target(9999)! == (7, true), "below everything: after the last row")
        XCTAssertNil(SwitcherViewModel.dropTarget(at: 0, in: [], rowHeight: 30, headerHeight: 20, spacing: 2))
    }

    private func snapshot(_ view: NSView, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.windowBackgroundColor.setFill()
        view.bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
