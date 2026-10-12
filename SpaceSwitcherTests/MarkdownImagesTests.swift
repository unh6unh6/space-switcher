import XCTest
@testable import SpaceSwitcher

/// #21: images in memos.
final class MarkdownImagesTests: XCTestCase {
    func testFindsImageLines() {
        let text = "앞\n![도식](images/a.png)\n  ![](<images/my file.png> \"제목\")  \n문장 안 ![x](b.png) 은 아님\n```\n![](c.png)\n```"
        let images = MarkdownImages.find(in: text)
        XCTAssertEqual(images.map(\.line), [1, 2])
        XCTAssertEqual(images.map(\.alt), ["도식", ""])
        XCTAssertEqual(images.map(\.source), ["images/a.png", "images/my file.png"])
    }

    func testRunsMarkImageLines() {
        let runs = MarkdownLiveStyle.runs(in: "![](a.png)\n**b**")
        XCTAssertEqual(runs.first?.kind, .image)
        XCTAssertEqual(runs.first?.line, 0)
        XCTAssertFalse(runs.contains { if case .link = $0.kind { return $0.line == 0 } else { return false } })
    }

    func testResolve() {
        let base = URL(fileURLWithPath: "/Users/me/Memos", isDirectory: true)
        XCTAssertEqual(MarkdownImages.resolve("images/a b.png", base: base)?.path, "/Users/me/Memos/images/a b.png")
        XCTAssertEqual(MarkdownImages.resolve("images/a%20b.png", base: base)?.path, "/Users/me/Memos/images/a b.png")
        XCTAssertEqual(MarkdownImages.resolve("/tmp/x.png", base: base)?.path, "/tmp/x.png")
        XCTAssertEqual(MarkdownImages.resolve("~/x.png", base: base)?.path, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("x.png").path)
        XCTAssertEqual(MarkdownImages.resolve("file:///tmp/y.png", base: base)?.path, "/tmp/y.png")
        XCTAssertEqual(MarkdownImages.resolve("https://e.com/z.png", base: base)?.absoluteString, "https://e.com/z.png")
        XCTAssertNil(MarkdownImages.resolve("images/a.png", base: nil))
    }

    func testDisplaySizeFitsWidthCapsHeightNeverEnlarges() {
        XCTAssertEqual(MarkdownImages.displaySize(natural: CGSize(width: 600, height: 300), width: 300), CGSize(width: 300, height: 150))
        XCTAssertEqual(MarkdownImages.displaySize(natural: CGSize(width: 300, height: 900), width: 300), CGSize(width: 80, height: 240))
        XCTAssertEqual(MarkdownImages.displaySize(natural: CGSize(width: 50, height: 40), width: 300), CGSize(width: 50, height: 40))
    }

    func testNamesForNewImages() {
        XCTAssertEqual(MarkdownImages.fileName(original: "도식.png", taken: []), "도식.png")
        XCTAssertEqual(MarkdownImages.fileName(original: "도식.png", taken: ["도식.png", "도식-2.png"]), "도식-3.png")
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "Asia/Seoul"),
                                  year: 2026, month: 10, day: 12, hour: 21, minute: 3, second: 5).date!
        XCTAssertEqual(MarkdownImages.fileName(original: nil, taken: [], date: date, timeZone: TimeZone(identifier: "Asia/Seoul")!),
                       "image-20261012-210305.png")
    }

    func testMarkdownForInsertedImage() {
        XCTAssertEqual(MarkdownImages.markdown(path: "images/a.png"), "![](images/a.png)")
        XCTAssertEqual(MarkdownImages.markdown(path: "images/my file.png"), "![](<images/my file.png>)")
    }
}
