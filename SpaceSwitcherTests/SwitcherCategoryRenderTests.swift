import AppKit
import SwiftUI
import XCTest
@testable import SpaceSwitcher

/// #35: grouped rows get a header each, and the list grows by exactly those headers.
/// Set TEST_RUNNER_SNAPSHOT_DIR=<dir> to also write a PNG for a visual check.
final class SwitcherCategoryRenderTests: XCTestCase {
    private func rows(grouped: Bool) -> [SwitcherViewModel.Row] {
        let titles = ["메일", "배포", "모니터링", "개인"]
        let groups: [String?] = grouped ? ["todo", nil, "monitoring", "미분류"] : [nil, nil, nil, nil]
        return titles.enumerated().map { i, title in
            var row = SwitcherViewModel.Row(id: "s\(i)", number: [2, 4, 1, 3][i], title: title, isNamed: true, isCurrent: i == 2)
            row.groupTitle = groups[i]
            return row
        }
    }

    private func height(grouped: Bool, name: String) -> CGFloat {
        let model = SwitcherViewModel()
        model.rows = rows(grouped: grouped)
        model.hasCategories = grouped
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
        XCTAssertEqual(grouped - plain, 3 * (SwitcherView.headerHeight + 2), accuracy: 1)
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
