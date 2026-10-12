import Foundation

/// Editing shortcuts for the memo editor (#21) as pure text transforms: given the text and the
/// selection (UTF-16), say what to replace and where the selection goes. `nil` = not applicable,
/// let the editor do its default (e.g. a plain newline).
enum MarkdownEditing {
    struct Replacement: Equatable {
        let range: NSRange
        let string: String
        /// Selection after the replacement, in the new text.
        let selection: NSRange
    }

    // MARK: ⌘B ⌘I ⌘E

    /// Wraps the selection in `marker` (or inserts a pair at the caret); unwraps if already wrapped.
    static func toggleWrap(_ marker: String, text: String, selection: NSRange) -> Replacement {
        let s = text as NSString
        let m = (marker as NSString).length
        let before = s.substring(to: selection.location)
        let after = s.substring(from: NSMaxRange(selection))
        let inner = s.substring(with: selection)

        func wrappedOutside() -> Bool {
            guard before.hasSuffix(marker), after.hasPrefix(marker) else { return false }
            // "*" next to "**": the bold markers are not an italic pair (but "***" holds one).
            guard marker == "*" else { return true }
            return !before.hasSuffix("**") || before.hasSuffix("***")
        }

        if wrappedOutside() {
            let range = NSRange(location: selection.location - m, length: selection.length + 2 * m)
            return Replacement(range: range, string: inner, selection: NSRange(location: range.location, length: selection.length))
        }
        let innerLength = (inner as NSString).length
        if innerLength >= 2 * m, inner.hasPrefix(marker), inner.hasSuffix(marker),
           marker != "*" || !inner.hasPrefix("**") || inner.hasPrefix("***") {
            let unwrapped = (inner as NSString).substring(with: NSRange(location: m, length: innerLength - 2 * m))
            return Replacement(range: selection, string: unwrapped,
                               selection: NSRange(location: selection.location, length: (unwrapped as NSString).length))
        }
        return Replacement(range: selection, string: marker + inner + marker,
                           selection: NSRange(location: selection.location + m, length: selection.length))
    }

    // MARK: ⌘K

    /// `[selection](url)` with "url" selected; a selected URL becomes the target instead.
    static func link(text: String, selection: NSRange) -> Replacement {
        let inner = (text as NSString).substring(with: selection)
        if inner.hasPrefix("http://") || inner.hasPrefix("https://") {
            return Replacement(range: selection, string: "[](\(inner))", selection: NSRange(location: selection.location + 1, length: 0))
        }
        if inner.isEmpty {
            return Replacement(range: selection, string: "[](url)", selection: NSRange(location: selection.location + 1, length: 0))
        }
        let urlStart = selection.location + 1 + (inner as NSString).length + 2
        return Replacement(range: selection, string: "[\(inner)](url)", selection: NSRange(location: urlStart, length: 3))
    }

    // MARK: ⌘L

    /// The caret's line becomes a task (`- [ ] `), or a task's box flips.
    static func toggleTask(text: String, selection: NSRange) -> Replacement {
        let s = text as NSString
        let lineRange = contentRange(ofLineAt: selection.location, in: s)
        let line = s.substring(with: lineRange)
        let prefix = ListPrefix(line)
        let new: String
        if let prefix, let checked = prefix.checked {
            let boxAt = prefix.indent.count + 3   // "- [" → the mark
            var chars = Array(line)
            chars[boxAt] = checked ? " " : "x"
            new = String(chars)
        } else if let prefix, prefix.kind == .bullet {
            new = prefix.indent + prefix.marker + " [ ] " + prefix.content
        } else {
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            new = indent + "- [ ] " + line.dropFirst(indent.count)
        }
        let delta = (new as NSString).length - lineRange.length
        let caret = max(lineRange.location, selection.location + delta)
        return Replacement(range: lineRange, string: new, selection: NSRange(location: caret, length: selection.length))
    }

    // MARK: Enter

    /// In a list item (or quote): continue it on the next line; on an empty item: end the list.
    static func newline(text: String, selection: NSRange) -> Replacement? {
        guard selection.length == 0 else { return nil }
        let s = text as NSString
        let lineRange = contentRange(ofLineAt: selection.location, in: s)
        let line = s.substring(with: lineRange)
        guard let prefix = ListPrefix(line) else { return nil }
        let prefixLength = (prefix.full as NSString).length
        guard selection.location >= lineRange.location + prefixLength else { return nil }

        if prefix.content.trimmingCharacters(in: .whitespaces).isEmpty {
            return Replacement(range: lineRange, string: "", selection: NSRange(location: lineRange.location, length: 0))
        }
        let next = "\n" + prefix.indent + prefix.continuation
        return Replacement(range: selection, string: next,
                           selection: NSRange(location: selection.location + (next as NSString).length, length: 0))
    }

    // MARK: Tab / ⇧Tab

    /// Indents (2 spaces) or outdents every list line the selection touches; nil if none is a list line.
    static func indent(text: String, selection: NSRange, outdent: Bool) -> Replacement? {
        let s = text as NSString
        let first = contentRange(ofLineAt: selection.location, in: s)
        let last = contentRange(ofLineAt: NSMaxRange(selection), in: s)
        let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let lines = s.substring(with: block).components(separatedBy: "\n")
        guard lines.contains(where: { ListPrefix($0) != nil }) else { return nil }

        var changed = false
        var caretShift = 0
        let newLines = lines.enumerated().map { index, line -> String in
            guard ListPrefix(line) != nil else { return line }
            if outdent {
                let remove = line.hasPrefix("\t") ? 1 : min(2, line.prefix(while: { $0 == " " }).count)
                if remove > 0 { changed = true }
                if index == 0 { caretShift = -remove }
                return String(line.dropFirst(remove))
            }
            changed = true
            if index == 0 { caretShift = 2 }
            return "  " + line
        }
        guard changed else { return nil }
        let new = newLines.joined(separator: "\n")
        let selectionOut = selection.length == 0
            ? NSRange(location: max(first.location, selection.location + caretShift), length: 0)
            : NSRange(location: block.location, length: (new as NSString).length)
        return Replacement(range: block, string: new, selection: selectionOut)
    }

    // MARK: -

    /// The line holding `offset`, without its newline.
    private static func contentRange(ofLineAt offset: Int, in s: NSString) -> NSRange {
        var start = min(offset, s.length)
        while start > 0, s.character(at: start - 1) != 10 { start -= 1 }
        var end = min(offset, s.length)
        while end < s.length, s.character(at: end) != 10 { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// A list or quote line's leading part: indent + marker (+ task box).
    private struct ListPrefix {
        enum Kind { case bullet, task, numbered, quote }
        let kind: Kind
        let indent: String
        let marker: String
        /// Task state, for tasks.
        let checked: Bool?
        let number: Int?
        let content: String

        /// Indent + marker (+ box) + one space, as written.
        var full: String {
            switch kind {
            case .task: return indent + marker + " [" + (checked == true ? "x" : " ") + "] "
            case .numbered, .bullet, .quote: return indent + marker + " "
            }
        }

        /// What the next line starts with (after the indent).
        var continuation: String {
            switch kind {
            case .task: return marker + " [ ] "
            case .numbered: return "\((number ?? 0) + 1)\(marker.last.map(String.init) ?? ".") "
            case .bullet, .quote: return marker + " "
            }
        }

        init?(_ line: String) {
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let body = Array(line.dropFirst(indent.count))
            self.indent = indent
            guard let first = body.first else { return nil }
            if "-*+".contains(first), body.count >= 2, body[1] == " " {
                if body.count >= 5, body[2] == "[", " xX".contains(body[3]), body[4] == "]", body.count == 5 || body[5] == " " {
                    kind = .task
                    marker = String(first)
                    checked = body[3] != " "
                    number = nil
                    content = String(body.dropFirst(min(6, body.count)))
                    return
                }
                kind = .bullet
                marker = String(first)
                checked = nil
                number = nil
                content = String(body.dropFirst(2))
                return
            }
            if first == ">", body.count >= 2, body[1] == " " {
                kind = .quote
                marker = ">"
                checked = nil
                number = nil
                content = String(body.dropFirst(2))
                return
            }
            let digits = body.prefix(while: \.isNumber)
            if !digits.isEmpty, digits.count < body.count, let n = Int(String(digits)) {
                let mark = body[digits.count]
                if mark == "." || mark == ")", digits.count + 1 < body.count, body[digits.count + 1] == " " {
                    kind = .numbered
                    marker = String(digits) + String(mark)
                    checked = nil
                    number = n
                    content = String(body.dropFirst(digits.count + 2))
                    return
                }
            }
            return nil
        }
    }
}
