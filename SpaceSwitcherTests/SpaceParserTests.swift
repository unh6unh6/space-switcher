import XCTest
@testable import SpaceSwitcher

final class SpaceParserTests: XCTestCase {
    private func space(_ id: Int, _ uuid: String, type: Int = 0) -> [String: Any] {
        ["ManagedSpaceID": id, "id64": id, "uuid": uuid, "type": type]
    }

    private func display(_ identifier: String, current: Int, _ spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": identifier, "Current Space": ["ManagedSpaceID": current], "Spaces": spaces]
    }

    func testParsesDesktopsInOrderWithOneBasedIndex() {
        let raw = [display("MAIN", current: 4, [space(3, "A"), space(4, "B")])]
        let spaces = SpaceParser.parse(raw, activeSpaceID: 4, mainDisplayID: "MAIN")
        XCTAssertEqual(spaces, [
            Space(id: "A", managedID: 3, index: 1, position: 0, isCurrent: false),
            Space(id: "B", managedID: 4, index: 2, position: 1, isCurrent: true),
        ])
    }

    func testSkipsFullscreenSpacesWithoutConsumingAnIndex() {
        let raw = [display("MAIN", current: 3, [space(3, "A"), space(9, "FS", type: 4), space(4, "B")])]
        let spaces = SpaceParser.parse(raw, activeSpaceID: 3, mainDisplayID: "MAIN")
        XCTAssertEqual(spaces.map(\.id), ["A", "B"])
        XCTAssertEqual(spaces.map(\.index), [1, 2])
        XCTAssertEqual(spaces.map(\.position), [0, 2])
    }

    func testActivePositionCountsFullscreenSpaces() {
        let raw = [display("MAIN", current: 9, [space(3, "A"), space(9, "FS", type: 4), space(4, "B")])]
        XCTAssertEqual(SpaceParser.activePosition(raw, activeSpaceID: 9, mainDisplayID: "MAIN"), 1)
        XCTAssertEqual(SpaceParser.activePosition(raw, activeSpaceID: 4, mainDisplayID: "MAIN"), 2)
        XCTAssertNil(SpaceParser.activePosition(raw, activeSpaceID: 42, mainDisplayID: "MAIN"))
    }

    // #40: Mission Control shows a thumbnail per Space, fullscreen ones included.
    func testCountIncludesFullscreenSpacesOfTheMainDisplay() {
        let raw = [display("OTHER", current: 7, [space(7, "X")]),
                   display("MAIN", current: 3, [space(3, "A"), space(9, "FS", type: 4), space(4, "B")])]
        XCTAssertEqual(SpaceParser.count(raw, mainDisplayID: "MAIN"), 3)
    }

    func testEmptyUUIDMapsToMainKey() {
        let raw = [display("MAIN", current: 1, [space(1, ""), space(2, "B")])]
        let spaces = SpaceParser.parse(raw, activeSpaceID: 1, mainDisplayID: "MAIN")
        XCTAssertEqual(spaces.first?.id, Space.mainKey)
    }

    func testPicksMainDisplayAmongSeveral() {
        let raw = [
            display("OTHER", current: 7, [space(7, "X")]),
            display("MAIN", current: 3, [space(3, "A")]),
        ]
        let spaces = SpaceParser.parse(raw, activeSpaceID: 3, mainDisplayID: "MAIN")
        XCTAssertEqual(spaces.map(\.id), ["A"])
    }

    // With "Displays have separate Spaces" off, the single entry is labelled "Main", not a UUID.
    func testFallsBackToFirstDisplayWhenMainIDDoesNotMatch() {
        let raw = [display("Main", current: 3, [space(3, "A")])]
        let spaces = SpaceParser.parse(raw, activeSpaceID: 3, mainDisplayID: "SOME-UUID")
        XCTAssertEqual(spaces.map(\.id), ["A"])
    }

    func testNoCurrentWhenActiveSpaceIsFullscreen() {
        let raw = [display("MAIN", current: 9, [space(3, "A"), space(9, "FS", type: 4)])]
        let spaces = SpaceParser.parse(raw, activeSpaceID: 9, mainDisplayID: "MAIN")
        XCTAssertFalse(spaces.contains(where: \.isCurrent))
    }

    func testMalformedInputYieldsEmptyList() {
        XCTAssertEqual(SpaceParser.parse([], activeSpaceID: 1, mainDisplayID: "MAIN"), [])
        XCTAssertEqual(SpaceParser.parse([["garbage": 1]], activeSpaceID: 1, mainDisplayID: "MAIN"), [])
    }
}
