import XCTest
@testable import SpaceSwitcher

final class MemoSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SpaceSwitcherTests.MemoSettings"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaults() {
        let s = MemoSettings.load(from: defaults)
        XCTAssertFalse(s.overlayEnabled)          // opt-in: a window floating over everything
        XCTAssertTrue(s.previewEnabled)           // Option+E preview (#20); hidden anyway while no memo exists
        XCTAssertEqual(s.opacity, 0.85)
        XCTAssertEqual(s.corner, .topRight)
        XCTAssertNil(s.frame)
        XCTAssertFalse(s.collapsed)
        XCTAssertFalse(s.hideWhenEmpty)
        XCTAssertNil(s.directoryPath)
    }

    func testRoundTrip() {
        var s = MemoSettings()
        s.overlayEnabled = true
        s.previewEnabled = false
        s.opacity = 0.5
        s.corner = .bottomLeft
        s.frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        s.collapsed = true
        s.hideWhenEmpty = true
        s.directoryPath = "/tmp/vault"
        s.save(to: defaults)
        XCTAssertEqual(MemoSettings.load(from: defaults), s)
    }

    func testOpacityIsClamped() {
        var s = MemoSettings()
        s.opacity = 0.05
        s.save(to: defaults)
        XCTAssertEqual(MemoSettings.load(from: defaults).opacity, MemoSettings.minOpacity)
        s.opacity = 3
        s.save(to: defaults)
        XCTAssertEqual(MemoSettings.load(from: defaults).opacity, 1)
    }

    func testUnknownCornerFallsBack() {
        defaults.set("middle", forKey: "memoCorner")
        XCTAssertEqual(MemoSettings.load(from: defaults).corner, .topRight)
    }

    // MARK: placement

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 320, height: 220)

    func testCornerPlacementKeepsAMargin() {
        let m = MemoSettings.margin
        XCTAssertEqual(MemoSettings.Corner.topRight.origin(for: size, in: screen),
                       CGPoint(x: 1440 - 320 - m, y: 900 - 220 - m))
        XCTAssertEqual(MemoSettings.Corner.bottomLeft.origin(for: size, in: screen), CGPoint(x: m, y: m))
    }

    // A saved frame from a bigger monitor must not leave the memo off screen.
    func testSavedFrameIsPulledBackOnScreen() {
        let off = CGRect(x: 2000, y: -500, width: 320, height: 220)
        let fixed = MemoSettings.clamp(off, to: screen)
        XCTAssertTrue(screen.contains(fixed))
        XCTAssertEqual(fixed.size, off.size)
    }

    func testFrameLargerThanScreenShrinks() {
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        XCTAssertTrue(screen.contains(MemoSettings.clamp(huge, to: screen)))
    }

    // MARK: per-desktop layout (#24)

    private let rectA = CGRect(x: 100, y: 100, width: 300, height: 200)
    private let rectB = CGRect(x: 900, y: 500, width: 250, height: 400)

    func testDesktopWithoutItsOwnLayoutUsesTheSharedOne() {
        var s = MemoSettings()
        s.frame = rectA
        s.collapsed = true
        XCTAssertEqual(s.layout(for: "A"), MemoSettings.Layout(frame: rectA, collapsed: true))
        XCTAssertEqual(MemoSettings().layout(for: "A"), MemoSettings.Layout(frame: nil, collapsed: false))
    }

    func testEachDesktopKeepsItsOwnFrameAndCollapse() {
        var s = MemoSettings()
        s.setLayout(.init(frame: rectA, collapsed: false), for: "A")
        s.setLayout(.init(frame: rectB, collapsed: true), for: "B")
        XCTAssertEqual(s.layout(for: "A"), .init(frame: rectA, collapsed: false))
        XCTAssertEqual(s.layout(for: "B"), .init(frame: rectB, collapsed: true))
        XCTAssertNil(s.frame)                       // the shared value is untouched
    }

    // A fullscreen app Space has no desktop id; it reads and writes the shared value.
    func testNoDesktopUsesSharedValue() {
        var s = MemoSettings()
        s.setLayout(.init(frame: rectB, collapsed: true), for: nil)
        XCTAssertEqual(s.frame, rectB)
        XCTAssertTrue(s.collapsed)
        XCTAssertEqual(s.layout(for: nil), .init(frame: rectB, collapsed: true))
    }

    // #32: dragging the collapsed bar moves the expanded memo too — same top-left, same height.
    func testMovingTheCollapsedBarMovesTheExpandedFrame() {
        var layout = MemoSettings.Layout(frame: CGRect(x: 100, y: 300, width: 320, height: 220), collapsed: true)
        layout.moveCollapsed(to: CGRect(x: 500, y: 700, width: 320, height: 34))
        XCTAssertEqual(layout.frame, CGRect(x: 500, y: 734 - 220, width: 320, height: 220))
        XCTAssertTrue(layout.collapsed)
    }

    func testMovingTheCollapsedBarWithoutAFrameUsesTheDefaultSize() {
        var layout = MemoSettings.Layout(frame: nil, collapsed: true)
        layout.moveCollapsed(to: CGRect(x: 10, y: 600, width: 280, height: 34))
        let h = MemoSettings.defaultSize.height
        XCTAssertEqual(layout.frame, CGRect(x: 10, y: 634 - h, width: 280, height: h))
    }

    func testLayoutsSurviveSaveAndLoad() {
        var s = MemoSettings()
        s.setLayout(.init(frame: rectA, collapsed: true), for: "A")
        s.save(to: defaults)
        XCTAssertEqual(MemoSettings.load(from: defaults).layout(for: "A"), .init(frame: rectA, collapsed: true))
    }

    // Picking a corner moves every desktop's memo there; collapse states stay as they were.
    func testResetPositionsKeepsCollapse() {
        var s = MemoSettings()
        s.frame = rectA
        s.setLayout(.init(frame: rectA, collapsed: true), for: "A")
        s.setLayout(.init(frame: rectB, collapsed: false), for: "B")
        s.resetPositions()
        XCTAssertNil(s.frame)
        XCTAssertEqual(s.layout(for: "A"), .init(frame: nil, collapsed: true))
        XCTAssertEqual(s.layout(for: "B"), .init(frame: nil, collapsed: false))
    }

    func testPruneForgetsRemovedDesktops() {
        var s = MemoSettings()
        s.setLayout(.init(frame: rectA, collapsed: false), for: "A")
        s.setLayout(.init(frame: rectB, collapsed: false), for: "GONE")
        s.pruneLayouts(keeping: ["A"])
        XCTAssertEqual(s.layouts.keys.sorted(), ["A"])
    }

    // MARK: read-only lock (#27)

    func testLockIsPerDesktop() {
        var s = MemoSettings()
        XCTAssertFalse(s.isLocked("A"))
        s.setLocked(true, for: "A")
        XCTAssertTrue(s.isLocked("A"))
        XCTAssertFalse(s.isLocked("B"))
        XCTAssertFalse(s.isLocked(nil))
        s.setLocked(false, for: "A")
        XCTAssertFalse(s.isLocked("A"))
    }

    func testLocksSurviveSaveAndPrune() {
        var s = MemoSettings()
        s.setLocked(true, for: "A")
        s.setLocked(true, for: "GONE")
        s.pruneLayouts(keeping: ["A"])
        s.save(to: defaults)
        let loaded = MemoSettings.load(from: defaults)
        XCTAssertTrue(loaded.isLocked("A"))
        XCTAssertFalse(loaded.isLocked("GONE"))
    }

    // MARK: background colors (#27 follow-up)

    func testBackgroundsDefaultToTheCurrentLook() {
        let s = MemoSettings.load(from: defaults)
        XCTAssertEqual(s.overlayBackground, .standard)
        XCTAssertNil(MemoSettings.Background.standard.rgb)       // the translucent HUD material
        XCTAssertNil(MemoSettings.Background.standard.isDark)    // text follows the system
    }

    func testBackgroundIsSaved() {
        var s = MemoSettings()
        s.overlayBackground = .yellow
        s.save(to: defaults)
        XCTAssertEqual(MemoSettings.load(from: defaults).overlayBackground, .yellow)
    }

    // Light paper gets dark text, black gets light text.
    func testTextContrastFollowsTheBackground() {
        XCTAssertEqual(MemoSettings.Background.white.isDark, false)
        XCTAssertEqual(MemoSettings.Background.yellow.isDark, false)
        XCTAssertEqual(MemoSettings.Background.black.isDark, true)
        XCTAssertEqual(MemoSettings.Background.allCases.count, 4)
    }

    func testUnknownBackgroundFallsBack() {
        defaults.set("purple", forKey: "memoOverlayBackground")
        XCTAssertEqual(MemoSettings.load(from: defaults).overlayBackground, .standard)
    }
}
