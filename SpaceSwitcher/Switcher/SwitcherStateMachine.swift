import Foundation

/// The switcher's behaviour from SPEC §3.1, free of UI and system events.
/// Selections are 0-based row indexes in display order (desktop order, or grouped by category, #35).
struct SwitcherStateMachine {
    enum State: Equatable {
        case idle
        /// Modifier still held. `pressCount` separates popup mode (1) from cycle mode (≥ 2).
        case holding(selection: Int, pressCount: Int)
        /// Panel stays open after a short press.
        case sticky(selection: Int)
        /// Inline rename in progress; keys belong to the text field.
        case renaming(selection: Int)
        /// Editing the selected desktop's description (#17); keys belong to the text editor.
        case describing(selection: Int)
    }

    enum Event: Equatable {
        /// Shortcut key K, with or without its modifier (the modifier is only held in Holding).
        /// Autorepeat is filtered out before it gets here.
        case trigger(shift: Bool)
        case modifierReleased
        case moveUp, moveDown
        /// Number key 1–9.
        case digit(Int)
        case confirm, cancel
        /// Row clicked: switch to it.
        case select(Int)
        /// Move the selection to a row without switching (first half of a double-click rename).
        case highlight(Int)
        case beginRename, endRename
        case beginDescribe, endDescribe
        /// Shift+↑↓: scroll the memo preview by a step (#20).
        case scrollMemo(Int)
        /// C: the selected desktop moves one row down, wrapping to the top (#44).
        case reorder
        case clickOutside
        /// The panel vanished without going through the machine (e.g. the app was hidden).
        case dismissed
    }

    enum Action: Equatable {
        case show(selection: Int)
        case select(Int)
        case hide
        /// Hide the panel and switch to this row.
        case switchTo(Int)
        /// Hide the panel and switch to "Desktop N" (a digit; rows may be grouped out of order, #35).
        case switchToDesktop(Int)
        case rename(Int)
        case describe(Int)
        case scrollMemo(Int)
        case reorder(Int)
    }

    private(set) var state: State = .idle
    private var count = 0
    /// Queried on every open: desktops may have been added or removed since last time.
    private let listProvider: () -> (count: Int, initial: Int)

    init(listProvider: @escaping () -> (count: Int, initial: Int)) {
        self.listProvider = listProvider
    }

    /// Holding and Sticky own the keyboard (the event tap swallows keys). Renaming hands keys to the text field.
    var isCapturingKeys: Bool {
        switch state {
        case .holding, .sticky: return true
        case .idle, .renaming, .describing: return false
        }
    }

    var isOpen: Bool { state != .idle }

    mutating func handle(_ event: Event) -> Action? {
        if event == .dismissed {
            return isOpen ? close(.hide) : nil
        }
        switch state {
        case .idle:
            guard case .trigger = event else { return nil }
            let list = listProvider()
            guard list.count > 0 else { return nil }
            count = list.count
            let initial = min(max(list.initial, 0), count - 1)
            state = .holding(selection: initial, pressCount: 1)
            return .show(selection: initial)

        case let .holding(selection, pressCount):
            switch event {
            case .trigger(let shift):
                let next = step(selection, shift ? -1 : 1)
                state = .holding(selection: next, pressCount: pressCount + 1)
                return .select(next)
            case .modifierReleased:
                if pressCount >= 2 { return close(.switchTo(selection)) }
                state = .sticky(selection: selection)
                return nil
            case .moveUp, .moveDown:
                return move(selection, event == .moveUp ? -1 : 1) { .holding(selection: $0, pressCount: pressCount) }
            case .highlight(let row) where (0..<count).contains(row):
                state = .holding(selection: row, pressCount: pressCount)
                return .select(row)
            case .scrollMemo(let step):
                return .scrollMemo(step)
            case .cancel, .clickOutside:
                return close(.hide)
            case .select(let row) where (0..<count).contains(row):
                return close(.switchTo(row))
            default:
                return nil
            }

        case let .sticky(selection):
            switch event {
            case .trigger(let shift):
                return move(selection, shift ? -1 : 1) { .sticky(selection: $0) }
            case .moveUp, .moveDown:
                return move(selection, event == .moveUp ? -1 : 1) { .sticky(selection: $0) }
            case .highlight(let row) where (0..<count).contains(row):
                state = .sticky(selection: row)
                return .select(row)
            case .scrollMemo(let step):
                return .scrollMemo(step)
            case .digit(let n) where (1...count).contains(n):
                return close(.switchToDesktop(n))
            case .reorder:
                return .reorder(selection)
            case .confirm:
                return close(.switchTo(selection))
            case .select(let row) where (0..<count).contains(row):
                return close(.switchTo(row))
            case .beginRename:
                state = .renaming(selection: selection)
                return .rename(selection)
            case .beginDescribe:
                state = .describing(selection: selection)
                return .describe(selection)
            case .cancel, .clickOutside:
                return close(.hide)
            default:
                return nil
            }

        case let .describing(selection):
            switch event {
            case .endDescribe:
                state = .sticky(selection: selection)
                return .select(selection)
            case .clickOutside:
                return close(.hide)
            default:
                return nil
            }

        case let .renaming(selection):
            switch event {
            case .endRename:
                state = .sticky(selection: selection)
                return .select(selection)
            case .clickOutside:
                return close(.hide)
            default:
                return nil
            }
        }
    }

    private func step(_ selection: Int, _ delta: Int) -> Int {
        ((selection + delta) % count + count) % count
    }

    private mutating func move(_ selection: Int, _ delta: Int, _ makeState: (Int) -> State) -> Action {
        let next = step(selection, delta)
        state = makeState(next)
        return .select(next)
    }

    private mutating func close(_ action: Action) -> Action {
        state = .idle
        return action
    }
}
