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

    // MARK: empty categories (#43) and moving rows (#44)

    func testShowingEmptyCategoriesListsEveryHeaderAndUncategorized() {
        var c = made(["todo", "doing", "done"])
        XCTAssertEqual(c.groups(spaces, showsEmpty: true).map(\.title), ["todo", "doing", "done", "미분류"],
                       "nothing assigned yet: the headers are there to move desktops under")
        c.assign("doing", to: "s2")
        let groups = c.groups(spaces, showsEmpty: true)
        XCTAssertEqual(groups.map(\.title), ["todo", "doing", "done", "미분류"])
        XCTAssertEqual(groups.map { $0.spaces.map(\.id) }, [[], ["s2"], [], ["s1", "s3", "s4", "s5"]])
        for s in spaces { c.assign("doing", to: s.id) }
        XCTAssertEqual(c.groups(spaces, showsEmpty: true).last?.spaces, [], "an empty 미분류 is shown too")
        XCTAssertEqual(DesktopCategories().groups(spaces, showsEmpty: true).map(\.title), [nil], "no categories: plain list")
    }

    private func rows(_ c: DesktopCategories) -> [String] {
        c.groups(spaces, showsEmpty: true).flatMap { g in [g.title.map { "[\($0)]" } ?? "[]"] + g.spaces.map(\.id) }
    }

    func testMoveDownStepsOneRowAndCrossesIntoTheNextCategory() {
        var c = made(["todo", "doing"])
        c.assign("todo", to: "s1")
        c.assign("todo", to: "s2")
        XCTAssertEqual(rows(c), ["[todo]", "s1", "s2", "[doing]", "[미분류]", "s3", "s4", "s5"])
        c.moveDown("s1", among: spaces)
        XCTAssertEqual(rows(c), ["[todo]", "s2", "s1", "[doing]", "[미분류]", "s3", "s4", "s5"])
        c.moveDown("s1", among: spaces)
        XCTAssertEqual(rows(c), ["[todo]", "s2", "[doing]", "s1", "[미분류]", "s3", "s4", "s5"], "past a header = into that category")
        XCTAssertEqual(c.category(for: "s1")?.id, "doing")
        c.moveDown("s1", among: spaces)
        XCTAssertNil(c.category(for: "s1"))
        XCTAssertEqual(rows(c), ["[todo]", "s2", "[doing]", "[미분류]", "s1", "s3", "s4", "s5"])
    }

    func testMoveDownFromTheBottomWrapsToTheTop() {
        var c = made(["todo"])
        c.moveDown("s5", among: spaces)
        XCTAssertEqual(rows(c), ["[todo]", "s5", "[미분류]", "s1", "s2", "s3", "s4"])
        XCTAssertEqual(c.category(for: "s5")?.id, "todo")

        var plain = DesktopCategories()
        plain.moveDown("s5", among: spaces)
        XCTAssertEqual(plain.ordered(spaces).map(\.id), ["s5", "s1", "s2", "s3", "s4"], "no categories: just the order")
        plain.moveDown("s1", among: spaces)
        XCTAssertEqual(plain.ordered(spaces).map(\.id), ["s5", "s2", "s1", "s3", "s4"])
    }

    func testDropBeforeOrAfterARowOrUnderAHeader() {
        var c = made(["todo", "doing"])
        c.assign("todo", to: "s1")
        c.move("s4", to: .space("s1"), after: false, among: spaces)
        XCTAssertEqual(rows(c), ["[todo]", "s4", "s1", "[doing]", "[미분류]", "s2", "s3", "s5"])
        c.move("s4", to: .header("doing"), after: true, among: spaces)
        XCTAssertEqual(rows(c), ["[todo]", "s1", "[doing]", "s4", "[미분류]", "s2", "s3", "s5"])
        c.move("s1", to: .space("s5"), after: true, among: spaces)
        XCTAssertEqual(rows(c), ["[todo]", "[doing]", "s4", "[미분류]", "s2", "s3", "s5", "s1"])
        XCTAssertNil(c.category(for: "s1"))
        c.move("s2", to: .space("s2"), after: true, among: spaces)    // onto itself: nothing changes
        XCTAssertEqual(rows(c), ["[todo]", "[doing]", "s4", "[미분류]", "s2", "s3", "s5", "s1"])
    }

    // New desktops join the bottom of their group; desktops that vanish keep their place for later.
    func testNewDesktopsGoLastAndVanishedOnesKeepTheirPlace() {
        var c = DesktopCategories()
        c.moveDown("s1", among: Array(spaces.prefix(3)))   // order now s2 s1 s3
        XCTAssertEqual(c.ordered(spaces).map(\.id), ["s2", "s1", "s3", "s4", "s5"])
        c.moveDown("s2", among: [space(1), space(2)])        // s3 is gone for now
        XCTAssertEqual(c.ordered(spaces).map(\.id), ["s1", "s2", "s3", "s4", "s5"])
    }

    // Data saved before #44 has no order: decoding keeps the categories and macOS order.
    func testDecodesDataFromBeforeTheOrder() throws {
        let old = #"{"categories":[{"id":"a","name":"todo"}],"assignments":{"s2":"a"}}"#
        let c = try JSONDecoder().decode(DesktopCategories.self, from: Data(old.utf8))
        XCTAssertEqual(c.category(for: "s2")?.name, "todo")
        XCTAssertEqual(c.ordered(spaces).map(\.id), ["s2", "s1", "s3", "s4", "s5"])
    }

    func testShowEmptySettingDefaultsOn() {
        let suite = "SpaceSwitcherTests.DesktopCategories.showsEmpty"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertTrue(DesktopCategories.showsEmpty(in: defaults))
        DesktopCategories.setShowsEmpty(false, in: defaults)
        XCTAssertFalse(DesktopCategories.showsEmpty(in: defaults))
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

    // MARK: feature switch (#42)

    func testFeatureIsOnByDefaultAndOffIgnoresCategoriesButKeepsThem() {
        let suite = "SpaceSwitcherTests.DesktopCategories.enabled"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var c = made(["todo"])
        c.assign("todo", to: "s2")
        c.save(to: defaults)
        XCTAssertTrue(DesktopCategories.isEnabled(in: defaults))
        XCTAssertEqual(DesktopCategories.active(from: defaults), c)

        DesktopCategories.setEnabled(false, in: defaults)
        XCTAssertFalse(DesktopCategories.isEnabled(in: defaults))
        XCTAssertEqual(DesktopCategories.active(from: defaults), DesktopCategories())   // plain list
        XCTAssertEqual(DesktopCategories.load(from: defaults), c)                       // data kept

        DesktopCategories.setEnabled(true, in: defaults)
        XCTAssertEqual(DesktopCategories.active(from: defaults), c)
    }
}
