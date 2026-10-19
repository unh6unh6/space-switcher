import Foundation

/// Keeps an always-editable memo (#27) and its file in step. The editor saves as you type; the folder
/// watcher reports every change, including our own writes. Compares trimmed text because the store
/// trims what it writes. Pure.
struct MemoSync {
    enum Decision: Equatable {
        /// Our own write, or nothing new.
        case ignore
        /// Changed outside and the editor has nothing unsaved: show the new text.
        case replace
        /// Changed outside while the editor has unsaved typing: keep typing, it is saved next.
        case keepLocal
    }

    /// What the file holds as far as we know (last loaded or saved).
    private var saved: String
    /// A template the editor started from (#36): unchanged, it is not worth a file. Cleared on save.
    private var template: String?

    init(loaded: String?) {
        saved = Self.normalized(loaded)
    }

    func needsSave(_ editorText: String) -> Bool {
        let text = Self.normalized(editorText)
        return text != saved && text != template
    }

    mutating func didSave(_ text: String) {
        saved = Self.normalized(text)
        template = nil
    }

    /// The editor was filled with a template for a desktop without a memo (#36).
    mutating func startFromTemplate(_ text: String) {
        template = Self.normalized(text)
    }

    /// Still exactly the template: leaving now should leave no memo behind.
    func isUntouchedTemplate(_ editorText: String) -> Bool {
        template != nil && Self.normalized(editorText) == template
    }

    func incoming(_ fileText: String?, editorText: String) -> Decision {
        let file = Self.normalized(fileText)
        if file == saved { return .ignore }
        return needsSave(editorText) ? .keepLocal : .replace
    }

    private static func normalized(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
