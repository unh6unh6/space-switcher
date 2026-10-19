import XCTest
@testable import SpaceSwitcher

/// #35: desktops grouped by user-defined categories in the switcher list.
final class DesktopCategoriesTests: XCTestCase {
    private func space(_ n: Int, current: Bool = false) -> Space {
        Space(id: "s\(n)", managedID: 100 + n, index: n, position: n - 1, isCurrent: current)
    }
    private lazy var spaces = (1...5).map { space($0) }

    private func made(_ names: [String]) -> DesktopCategories {
        var c = DesktopCategories()
        for name in names { XCTAssertTrue(c.add(name, id: name)) }
        return c
    }

    private func titles(_ c: DesktopCategories) -> [String?] { c.groups(spaces).map(\.title) }
    private func ids(_ c: DesktopCategories) -> [[String]] { c.groups(spaces).map { $0.spaces.map(\.id) } }

    func testNoCategoriesKeepsThePlainList() {
        XCTAssertEqual(titles(DesktopCategories()), [nil])
        XCTAssertEqual(ids(DesktopCategories()), [["s1", "s2", "s3", "s4", "s5"]])
        // Categories made but nothing assigned yet: still the plain list, no "미분류" header.
        XCTAssertEqual(titles(made(["todo"])), [nil])
    }

    func testGroupsInCategoryOrderThenUncategorizedLast() {
        var c = made(["todo", "inprogress", "monitoring"])
        c.assign("inprogress", to: "s1")
        c.assign("todo", to: "s4")
        c.assign("todo", to: "s2")
        XCTAssertEqual(titles(c), ["todo", "inprogress", "미분류"])
        XCTAssertEqual(ids(c), [["s2", "s4"], ["s1"], ["s3", "s5"]], "macOS order inside a group; empty groups left out")
        XCTAssertEqual(c.ordered(spaces).map(\.index), [2, 4, 1, 3, 5])
    }

    func testEveryDesktopCategorizedHasNoUncategorizedGroup() {
        var c = made(["a"])
        for s in spaces { c.assign("a", to: s.id) }
        XCTAssertEqual(titles(c), ["a"])
    }

    func testCycleGoesThroughCategoriesThenBackToNone() {
        var c = made(["todo", "doing"])
        c.cycle("s1")
        XCTAssertEqual(c.category(for: "s1")?.name, "todo")
        c.cycle("s1")
        XCTAssertEqual(c.category(for: "s1")?.name, "doing")
        c.cycle("s1")
        XCTAssertNil(c.category(for: "s1"))
        var empty = DesktopCategories()
        empty.cycle("s1")
        XCTAssertNil(empty.category(for: "s1"), "nothing to cycle through")
    }

    func testAddTrimsCapsAndRejectsDuplicatesOrBlank() {
        var c = DesktopCategories()
        XCTAssertTrue(c.add("  todo  ", id: "1"))
        XCTAssertFalse(c.add("todo", id: "2"))
        XCTAssertFalse(c.add("   ", id: "3"))
        XCTAssertTrue(c.add(String(repeating: "가", count: 40), id: "4"))
        XCTAssertEqual(c.categories.map(\.name), ["todo", String(repeating: "가", count: DesktopCategories.maxNameLength)])
    }

    func testRenameKeepsAssignments() {
        var c = made(["todo"])
        c.assign("todo", to: "s3")
        c.rename("todo", to: "할 일")
        XCTAssertEqual(c.category(for: "s3")?.name, "할 일")
        c.rename("todo", to: "  ")          // blank: ignored
        XCTAssertEqual(c.categories.first?.name, "할 일")
    }

    func testRemoveUncategorizesItsDesktops() {
        var c = made(["a", "b"])
        c.assign("a", to: "s1")
        c.assign("b", to: "s2")
        c.remove("a")
        XCTAssertNil(c.category(for: "s1"))
        XCTAssertEqual(c.category(for: "s2")?.name, "b")
        XCTAssertEqual(c.categories.map(\.id), ["b"])
    }

    func testMoveChangesGroupOrder() {
        var c = made(["a", "b", "c"])
        c.move("c", by: -1)
        XCTAssertEqual(c.categories.map(\.id), ["a", "c", "b"])
        c.move("a", by: -1)                 // already first
        XCTAssertEqual(c.categories.map(\.id), ["a", "c", "b"])
    }

    func testAssignToUnknownCategoryIsIgnored() {
        var c = made(["a"])
        c.assign("zzz", to: "s1")
        XCTAssertNil(c.category(for: "s1"))
        c.assign("a", to: "s1")
        c.assign(nil, to: "s1")
        XCTAssertNil(c.category(for: "s1"))
    }

    func testSaveAndLoad() {
        let suite = "SpaceSwitcherTests.DesktopCategories"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var c = made(["todo", "doing"])
        c.assign("doing", to: "s2")
        c.save(to: defaults)
        XCTAssertEqual(DesktopCategories.load(from: defaults), c)
        XCTAssertEqual(DesktopCategories.load(from: UserDefaults(suiteName: suite + ".empty")!), DesktopCategories())
    }
}
