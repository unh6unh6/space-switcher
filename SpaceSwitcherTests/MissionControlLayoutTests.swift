import XCTest
@testable import SpaceSwitcher

// #40: what Mission Control shows, read from the window list (numbers from spike/mcoverlay.swift on macOS 27).
final class MissionControlLayoutTests: XCTestCase {
    private typealias W = MissionControlLayout.Window
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let wallpaper = W(id: 1, owner: "WindowManager", layer: -2147483624, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private let backdrop = W(id: 2, owner: "WindowManager", layer: 19, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private let bar = W(id: 3, owner: "WindowManager", layer: 14, bounds: CGRect(x: 0, y: 0, width: 1920, height: 96))

    private func thumb(_ id: Int, x: CGFloat, y: CGFloat = 37) -> W {
        W(id: id, owner: "WindowManager", layer: 15, bounds: CGRect(x: x, y: y, width: 190, height: 129))
    }

    func testClosedWhenOnlyTheWallpaperIsThere() {
        XCTAssertEqual(MissionControlLayout.state([wallpaper], display: display), .closed)
    }

    func testOpenWithACollapsedBarHasNoThumbnails() {
        XCTAssertEqual(MissionControlLayout.state([wallpaper, backdrop, bar], display: display), .open([]))
    }

    func testExpandedBarListsThumbnailsLeftToRight() {
        let windows = [wallpaper, backdrop, bar, thumb(12, x: 1057), thumb(10, x: 673), thumb(11, x: 865)]
        XCTAssertEqual(MissionControlLayout.state(windows, display: display),
                       .open([thumb(10, x: 673), thumb(11, x: 865), thumb(12, x: 1057)].map(\.thumbnail)))
    }

    // Window thumbnails (layer 0) and app name tags (layer 2) in the middle are not desktops.
    func testIgnoresOtherWindows() {
        let windows = [backdrop, bar, thumb(10, x: 673),
                       W(id: 20, owner: "WindowManager", layer: 0, bounds: CGRect(x: 11, y: 505, width: 810, height: 417)),
                       W(id: 21, owner: "WindowManager", layer: 2, bounds: CGRect(x: 288, y: 638, width: 316, height: 90)),
                       W(id: 22, owner: "Dock", layer: 15, bounds: CGRect(x: 0, y: 37, width: 190, height: 129))]
        XCTAssertEqual(MissionControlLayout.state(windows, display: display), .open([thumb(10, x: 673).thumbnail]))
    }

    // Only the main display's bar: thumbnails on a second monitor are skipped.
    func testIgnoresThumbnailsOnOtherDisplays() {
        let windows = [backdrop, bar, thumb(10, x: 673), thumb(30, x: 2500)]
        XCTAssertEqual(MissionControlLayout.state(windows, display: display), .open([thumb(10, x: 673).thumbnail]))
    }

    // The bar alone (as it slides away on close) still counts as open; no backdrop and no bar = closed.
    func testBarWithoutBackdropIsStillOpen() {
        XCTAssertEqual(MissionControlLayout.state([bar], display: display), .open([]))
    }

    // MARK: matching thumbnails to Spaces

    private let three = [MissionControlLayout.Thumbnail(id: 10, frame: .zero),
                         MissionControlLayout.Thumbnail(id: 11, frame: .zero),
                         MissionControlLayout.Thumbnail(id: 12, frame: .zero)]

    func testFirstMatchIsLeftToRightSpaceOrder() {
        XCTAssertEqual(MissionControlLayout.match(three, spaceCount: 3, previous: [:]), [10: 0, 11: 1, 12: 2])
    }

    // Thumbnails slide in one by one; until all are there we can't tell which is which.
    func testNoMatchWhileTheCountDiffers() {
        XCTAssertEqual(MissionControlLayout.match(Array(three.prefix(2)), spaceCount: 3, previous: [:]), [:])
    }

    // Dragging a thumbnail to reorder changes the x order, but each window keeps its desktop.
    func testKnownWindowsKeepTheirSpaceWhileDragged() {
        let dragged = [three[1], three[0], three[2]]
        XCTAssertEqual(MissionControlLayout.match(dragged, spaceCount: 3, previous: [10: 0, 11: 1, 12: 2]),
                       [10: 0, 11: 1, 12: 2])
    }

    // Reopening Mission Control creates new windows: match afresh.
    func testNewWindowsAreMatchedAfresh() {
        let reopened = [MissionControlLayout.Thumbnail(id: 20, frame: .zero), MissionControlLayout.Thumbnail(id: 21, frame: .zero)]
        XCTAssertEqual(MissionControlLayout.match(reopened, spaceCount: 2, previous: [10: 0, 11: 1]), [20: 0, 21: 1])
    }

    // MARK: label placement

    // On the thumbnail window's bottom edge, where macOS draws its "데스크탑 N" caption, in AppKit
    // coordinates (y grows upward from the primary screen's bottom).
    func testLabelCoversTheCaptionStrip() {
        let thumbnail = CGRect(x: 673, y: 37, width: 190, height: 129)
        let frame = MissionControlLayout.labelFrame(size: CGSize(width: 120, height: 22), thumbnail: thumbnail, primaryHeight: 1080)
        XCTAssertEqual(frame, CGRect(x: 673 + 35, y: 1080 - 166, width: 120, height: 22))
    }

    // A short name is still wide enough to hide the caption; a long one stops at the thumbnail's width.
    func testLabelWidthIsBetweenTheCaptionAndTheThumbnail() {
        let thumbnail = CGRect(x: 0, y: 37, width: 190, height: 129)
        let short = MissionControlLayout.labelFrame(size: CGSize(width: 30, height: 22), thumbnail: thumbnail, primaryHeight: 1080)
        XCTAssertEqual(short.width, MissionControlLayout.labelMinWidth)
        XCTAssertEqual(short.midX, thumbnail.midX)
        let long = MissionControlLayout.labelFrame(size: CGSize(width: 400, height: 22), thumbnail: thumbnail, primaryHeight: 1080)
        XCTAssertEqual(long.width, 190)
    }
}
