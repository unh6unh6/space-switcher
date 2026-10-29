import CoreGraphics

/// Translates raw key events into switcher events and decides whether the event tap swallows them.
/// Pure so the rules can be tested without a real tap.
enum KeyMapper {
    enum Decision: Equatable {
        /// Let the key reach the frontmost app.
        case pass
        /// Swallow the key; forward the event to the state machine if there is one.
        case consume(SwitcherStateMachine.Event?)
    }

    private static let modifierMask: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
    private static let shift = CGEventFlags.maskShift.rawValue

    /// - Parameter capturing: the panel is open and owns the keyboard (Holding or Sticky).
    static func map(keyCode: UInt16, flags: UInt64, isAutorepeat: Bool,
                    shortcut: Shortcut, capturing: Bool) -> Decision {
        let mods = flags & modifierMask
        let shiftDown = mods & shift != 0

        if keyCode == shortcut.keyCode && matches(mods, shortcut) {
            // Shift reverses direction, unless Shift is part of the shortcut itself.
            let reverse = shiftDown && shortcut.modifiers & shift == 0
            return .consume(isAutorepeat ? nil : .trigger(shift: reverse))
        }
        guard capturing else { return .pass }

        switch keyCode {
        case shortcut.keyCode where mods & ~shift == 0:  // plain K / Shift+K in Sticky
            return .consume(isAutorepeat ? nil : .trigger(shift: shiftDown))
        case KeyCode.escape: return .consume(.cancel)
        case KeyCode.returnKey, KeyCode.keypadEnter: return .consume(.confirm)
        case KeyCode.upArrow: return .consume(shiftDown ? .scrollMemo(-1) : .moveUp)
        case KeyCode.downArrow: return .consume(shiftDown ? .scrollMemo(1) : .moveDown)
        case KeyCode.r: return .consume(isAutorepeat ? nil : .beginRename)
        case KeyCode.d: return .consume(isAutorepeat ? nil : .beginDescribe)
        case KeyCode.c: return .consume(isAutorepeat ? nil : .reorder)
        default:
            if let i = KeyCode.digits.firstIndex(of: keyCode) { return .consume(.digit(i + 1)) }
            return .consume(nil)
        }
    }

    /// True the moment the shortcut's modifiers stop being all held (the cycle-mode commit point).
    static func modifierReleased(previous: UInt64, current: UInt64, shortcut: Shortcut) -> Bool {
        let wanted = shortcut.modifiers & modifierMask
        return previous & wanted == wanted && current & wanted != wanted
    }

    private static func matches(_ mods: UInt64, _ shortcut: Shortcut) -> Bool {
        let wanted = shortcut.modifiers & modifierMask
        if wanted & shift != 0 { return mods == wanted }
        return mods & ~shift == wanted
    }
}
