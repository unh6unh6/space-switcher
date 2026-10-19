import CoreGraphics
import Foundation

/// The switcher shortcut: one key plus one or more modifiers (`CGEventFlags` raw bits).
struct Shortcut: Equatable, Codable {
    let keyCode: UInt16
    let modifiers: UInt64

    static let `default` = Shortcut(keyCode: KeyCode.e, modifiers: CGEventFlags.maskAlternate.rawValue)

    // MARK: validation

    enum Problem: Equatable {
        /// Needs Control, Option or Command (Shift alone would eat capital letters).
        case needsModifier
        /// The "key" is itself a modifier.
        case modifierOnly
        /// Esc, Return, ↑/↓, R, D and 1–9 already drive the open panel.
        case reservedKey
    }

    private static let ctrl = CGEventFlags.maskControl.rawValue
    private static let opt = CGEventFlags.maskAlternate.rawValue
    private static let cmd = CGEventFlags.maskCommand.rawValue
    private static let shift = CGEventFlags.maskShift.rawValue
    /// kVK_RightCommand (54) … kVK_Function (63).
    private static let modifierKeyCodes: ClosedRange<UInt16> = 54...63
    private static let reservedKeys: Set<UInt16> = Set([KeyCode.escape, KeyCode.returnKey, KeyCode.keypadEnter,
                                                        KeyCode.upArrow, KeyCode.downArrow, KeyCode.r, KeyCode.d] + KeyCode.digits)

    var problem: Problem? {
        if Self.modifierKeyCodes.contains(keyCode) { return .modifierOnly }
        if modifiers & (Self.ctrl | Self.opt | Self.cmd) == 0 { return .needsModifier }
        if Self.reservedKeys.contains(keyCode) { return .reservedKey }
        return nil
    }

    // MARK: persistence

    static let defaultsKey = "switcherShortcut"
    static let didChange = Notification.Name("Shortcut.didChange")

    static func stored(in defaults: UserDefaults = .standard) -> Shortcut {
        guard let data = defaults.data(forKey: defaultsKey),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
              shortcut.problem == nil else { return .default }
        return shortcut
    }

    /// Ignored if invalid, so a bad value can never lock the user out of the switcher.
    func store(in defaults: UserDefaults = .standard) {
        guard problem == nil, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: display

    /// "⌃⌥⇧⌘" in Apple's order, then the key name.
    func display(keyName: String) -> String {
        let symbols: [(UInt64, String)] = [(Self.ctrl, "⌃"), (Self.opt, "⌥"), (Self.shift, "⇧"), (Self.cmd, "⌘")]
        let prefix = symbols.filter { modifiers & $0.0 != 0 }.map(\.1).joined()
        return prefix + (keyName.count == 1 ? keyName.uppercased() : keyName)
    }
}

/// Virtual key codes (ANSI layout positions, independent of the input language).
enum KeyCode {
    static let e: UInt16 = 14
    static let r: UInt16 = 15
    static let d: UInt16 = 2
    static let c: UInt16 = 8
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    /// Top-row 1…9.
    static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
}
