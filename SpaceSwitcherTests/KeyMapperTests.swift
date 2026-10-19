import CoreGraphics
import XCTest
@testable import SpaceSwitcher

final class KeyMapperTests: XCTestCase {
    private let optE = Shortcut.default  // Option+E
    private let opt = CGEventFlags.maskAlternate.rawValue
    private let shift = CGEventFlags.maskShift.rawValue
    private let cmd = CGEventFlags.maskCommand.rawValue
    private let ctrl = CGEventFlags.maskControl.rawValue

    private func map(_ key: UInt16, _ flags: UInt64, repeat isRepeat: Bool = false,
                     capturing: Bool = false, shortcut: Shortcut? = nil) -> KeyMapper.Decision {
        KeyMapper.map(keyCode: key, flags: flags, isAutorepeat: isRepeat,
                      shortcut: shortcut ?? optE, capturing: capturing)
    }

    // MARK: shortcut (works while idle)

    func testShortcutTriggersEvenWhenIdle() {
        XCTAssertEqual(map(KeyCode.e, opt), .consume(.trigger(shift: false)))
        XCTAssertEqual(map(KeyCode.e, opt | shift), .consume(.trigger(shift: true)))
    }

    // Non-modifier flag bits (caps lock, fn, device bits) must not break matching.
    func testIgnoresUnrelatedFlagBits() {
        let noise = CGEventFlags.maskAlphaShift.rawValue | CGEventFlags.maskNonCoalesced.rawValue | 0x20
        XCTAssertEqual(map(KeyCode.e, opt | noise), .consume(.trigger(shift: false)))
    }

    func testAutorepeatOfShortcutIsSwallowedButIgnored() {  // user decision: holding K does not cycle
        XCTAssertEqual(map(KeyCode.e, opt, repeat: true), .consume(nil))
    }

    func testOtherCombosPassThroughWhenIdle() {
        XCTAssertEqual(map(KeyCode.e, 0), .pass)              // plain E types normally
        XCTAssertEqual(map(KeyCode.e, opt | cmd), .pass)      // Cmd+Option+E belongs to other apps
        XCTAssertEqual(map(KeyCode.escape, 0), .pass)
        XCTAssertEqual(map(KeyCode.digits[0], 0), .pass)
    }

    func testShortcutThatIncludesShiftHasNoReverse() {
        let ctrlShiftX = Shortcut(keyCode: 7, modifiers: ctrl | shift)
        XCTAssertEqual(map(7, ctrl | shift, shortcut: ctrlShiftX), .consume(.trigger(shift: false)))
        XCTAssertEqual(map(7, ctrl, shortcut: ctrlShiftX), .pass)
    }

    // MARK: while the panel owns the keyboard

    func testPlainKMovesInSticky() {
        XCTAssertEqual(map(KeyCode.e, 0, capturing: true), .consume(.trigger(shift: false)))
        XCTAssertEqual(map(KeyCode.e, shift, capturing: true), .consume(.trigger(shift: true)))
    }

    func testNavigationKeys() {
        XCTAssertEqual(map(KeyCode.escape, 0, capturing: true), .consume(.cancel))
        XCTAssertEqual(map(KeyCode.returnKey, 0, capturing: true), .consume(.confirm))
        XCTAssertEqual(map(KeyCode.keypadEnter, 0, capturing: true), .consume(.confirm))
        XCTAssertEqual(map(KeyCode.upArrow, 0, capturing: true), .consume(.moveUp))
        XCTAssertEqual(map(KeyCode.downArrow, 0, capturing: true), .consume(.moveDown))
        XCTAssertEqual(map(KeyCode.r, 0, capturing: true), .consume(.beginRename))
    }

    func testDigitsOneToNine() {
        for (i, key) in KeyCode.digits.enumerated() {
            XCTAssertEqual(map(key, 0, capturing: true), .consume(.digit(i + 1)))
        }
        // Still Holding with Option down: Option+3 selects desktop 3 too.
        XCTAssertEqual(map(KeyCode.digits[2], opt, capturing: true), .consume(.digit(3)))
    }

    func testShiftArrowsScrollMemo() {
        let shift = CGEventFlags.maskShift.rawValue
        XCTAssertEqual(map(KeyCode.downArrow, shift, capturing: true), .consume(.scrollMemo(1)))
        XCTAssertEqual(map(KeyCode.upArrow, shift, capturing: true), .consume(.scrollMemo(-1)))
        XCTAssertEqual(map(KeyCode.downArrow, shift, repeat: true, capturing: true), .consume(.scrollMemo(1)))
        XCTAssertEqual(map(KeyCode.downArrow, opt | shift, capturing: true), .consume(.scrollMemo(1)))  // still holding ⌥
    }

    func testArrowAutorepeatStillMoves() {
        XCTAssertEqual(map(KeyCode.downArrow, 0, repeat: true, capturing: true), .consume(.moveDown))
    }

    func testDescribeKey() {
        XCTAssertEqual(map(KeyCode.d, 0, capturing: true), .consume(.beginDescribe))
        XCTAssertEqual(map(KeyCode.d, 0, repeat: true, capturing: true), .consume(nil))
        XCTAssertEqual(map(KeyCode.d, 0), .pass)   // idle: typing "d" is untouched
    }

    // #35: C moves the selected desktop to the next category.
    func testCategoryKey() {
        XCTAssertEqual(map(KeyCode.c, 0, capturing: true), .consume(.cycleCategory))
        XCTAssertEqual(map(KeyCode.c, 0, repeat: true, capturing: true), .consume(nil))
        XCTAssertEqual(map(KeyCode.c, 0), .pass)
    }

    func testRenameKeyAutorepeatIgnored() {
        XCTAssertEqual(map(KeyCode.r, 0, repeat: true, capturing: true), .consume(nil))
    }

    func testUnknownKeysAreSwallowedWhileCapturing() {
        XCTAssertEqual(map(0 /* A */, 0, capturing: true), .consume(nil))
    }

    // MARK: modifier release

    func testModifierReleaseDetection() {
        XCTAssertTrue(KeyMapper.modifierReleased(previous: opt, current: 0, shortcut: optE))
        XCTAssertTrue(KeyMapper.modifierReleased(previous: opt | shift, current: shift, shortcut: optE))
        XCTAssertFalse(KeyMapper.modifierReleased(previous: opt | shift, current: opt, shortcut: optE))  // only Shift let go
        XCTAssertFalse(KeyMapper.modifierReleased(previous: 0, current: 0, shortcut: optE))
        XCTAssertFalse(KeyMapper.modifierReleased(previous: 0, current: opt, shortcut: optE))
    }

    func testMultiModifierShortcutReleasesWhenAnyGoesUp() {
        let ctrlOptSpace = Shortcut(keyCode: 49, modifiers: ctrl | opt)
        XCTAssertTrue(KeyMapper.modifierReleased(previous: ctrl | opt, current: ctrl, shortcut: ctrlOptSpace))
    }
}
