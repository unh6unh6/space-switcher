import Foundation

/// One styled stretch of a memo's source (#27). Ranges are UTF-16 (`NSString`) offsets.
struct LiveStyleRun: Equatable {
    enum Kind: Equatable {
        /// Markdown markers: hidden away from the caret line, dimmed on it.
        case syntax
        /// Heading text, level 1…3 (4–6 look like 3).
        case heading(Int)
        case bold, italic, code, strike
        case link(String)
        /// The `-`/`*`/`+` of a bullet: drawn as • away from the caret line.
        case bullet
        /// The `[ ]`/`[x]` of a task: drawn as a checkbox away from the caret line.
        case task(checked: Bool)
        /// Text of a checked task.
        case done
        case quote
        /// The backticks of a ``` line, the text after them (an opening fence's "language"; hidden
        /// like the backticks away from the caret), and the lines between the fences.
        case fence, fenceInfo, codeBlock
        /// `---`: drawn as a line away from the caret line.
        case rule
        /// A whole line of a pipe table (#21): hidden and drawn as a table away from the caret.
        case table
    }

    let range: NSRange
    let line: Int
    let kind: Kind
}

/// Live-preview styling for the memo editor (#27): the text stays the Markdown source, and these runs
/// say which characters to hide, restyle or draw over. Covers the `MarkdownBlocks` subset plus inline
/// bold/italic/code/strike/links. Pure.
enum MarkdownLiveStyle {
    static func runs(in text: String) -> [LiveStyleRun] {
        let s = text as NSString
        var runs: [LiveStyleRun] = []
        let tableLines = Set(MarkdownTables.find(in: text).flatMap { Array($0.lines) })
        var fenceTicks = 0   // backticks of the open fence; 0 = not in a code block
        var line = 0
        var start = 0
        while start <= s.length {
            let end = lineEnd(s, from: start)
            let lineRange = NSRange(location: start, length: end - start)
            let trimmed = s.substring(with: lineRange).trimmingCharacters(in: .whitespaces)
            func add(_ location: Int, _ length: Int, _ kind: LiveStyleRun.Kind) {
                if length > 0 { runs.append(LiveStyleRun(range: NSRange(location: location, length: length), line: line, kind: kind)) }
            }

            let ticks = trimmed.prefix(while: { $0 == "`" }).count
            let tickStart = start + (s.substring(with: lineRange) as NSString)
                .range(of: "`").location.clampedToZero
            if tableLines.contains(line) {
                add(start, end - start, .table)
                let delimiterRow = !trimmed.isEmpty && trimmed.allSatisfy { "|-: ".contains($0) }
                if delimiterRow {
                    add(start, end - start, .syntax)
                } else {
                    for i in start..<end where s.character(at: i) == 124 && (i == start || s.character(at: i - 1) != 92) {
                        add(i, 1, .syntax)
                    }
                }
            } else if fenceTicks > 0 {
                // Any ``` line closes; text after it is hidden like an opening fence's info.
                if ticks >= 3 {
                    add(tickStart, ticks, .fence)
                    add(tickStart + ticks, end - tickStart - ticks, .fenceInfo)
                    fenceTicks = 0
                } else {
                    add(start, end - start, .codeBlock)
                }
            } else if ticks >= 3 && !isInlineFence(trimmed) {
                add(tickStart, ticks, .fence)
                add(tickStart + ticks, end - tickStart - ticks, .fenceInfo)
                fenceTicks = ticks
            } else {
                block(s, start, end, add: add)
            }

            guard end < s.length else { break }
            start = end + 1   // past "\n"
            line += 1
        }
        return runs
    }

    /// Caret lines widened to whole tables: a table shows its source all at once (#21).
    static func expand(_ lines: ClosedRange<Int>, in text: String) -> ClosedRange<Int> {
        var lower = lines.lowerBound, upper = lines.upperBound
        for table in MarkdownTables.find(in: text) where table.lines.overlaps(lines) {
            lower = min(lower, table.lines.lowerBound)
            upper = max(upper, table.lines.upperBound)
        }
        return lower...upper
    }

    /// Inline Markdown as shown (markers dropped), with the styles to apply: for table cells (#21).
    static func displayInline(_ source: String) -> (text: String, runs: [LiveStyleRun]) {
        let s = source as NSString
        var all: [LiveStyleRun] = []
        inline(s, 0, s.length) { location, length, kind in
            if length > 0 { all.append(LiveStyleRun(range: NSRange(location: location, length: length), line: 0, kind: kind)) }
        }
        let hidden = all.filter { $0.kind == .syntax }.map(\.range)
        func shown(_ offset: Int) -> Int { offset - hidden.filter { NSMaxRange($0) <= offset }.reduce(0) { $0 + $1.length } }
        var text = ""
        var cursor = 0
        for r in hidden.sorted(by: { $0.location < $1.location }) {
            text += s.substring(with: NSRange(location: cursor, length: r.location - cursor))
            cursor = NSMaxRange(r)
        }
        text += s.substring(from: cursor)
        let runs = all.filter { $0.kind != .syntax }.map {
            LiveStyleRun(range: NSRange(location: shown($0.range.location), length: $0.range.length), line: 0, kind: $0.kind)
        }
        return (text, runs)
    }

    /// Lines the selection touches; the caret line(s) show their raw source.
    static func lines(touching selection: NSRange, in text: String) -> ClosedRange<Int> {
        let first = line(at: selection.location, in: text)
        let last = line(at: NSMaxRange(selection), in: text)
        return first...max(first, last)
    }

    static func line(at offset: Int, in text: String) -> Int {
        let s = text as NSString
        let upTo = min(max(0, offset), s.length)
        var count = 0
        for i in 0..<upTo where s.character(at: i) == newline { count += 1 }
        return count
    }

    static func lineCount(_ text: String) -> Int {
        line(at: (text as NSString).length, in: text) + 1
    }

    /// Keeps a "to start/end of line" move on the caret's own line (#29). Away from the caret, lines
    /// hide their leading markers as null glyphs, which AppKit lays out at the end of the previous
    /// line fragment, so the stock move can land on a neighbouring line.
    static func clamp(_ target: Int, from caret: Int, towardEnd: Bool, in text: String) -> Int {
        let line = line(at: caret, in: text)
        guard self.line(at: target, in: text) != line else { return target }
        let start = lineStart(line, in: text)
        if !towardEnd { return start }
        let s = text as NSString
        return start + lineEnd(s, from: start) - start
    }

    /// UTF-16 offset where `line` begins (the end of the text past the last line).
    static func lineStart(_ line: Int, in text: String) -> Int {
        let s = text as NSString
        var start = 0
        for _ in 0..<max(0, line) {
            let end = lineEnd(s, from: start)
            guard end < s.length else { return s.length }
            start = end + 1
        }
        return start
    }

    // MARK: - blocks

    /// "```code```" on one line: inline code rather than a fence (chat-style writing).
    private static func isInlineFence(_ trimmed: String) -> Bool {
        let ticks = trimmed.prefix(while: { $0 == "`" }).count
        let rest = trimmed.dropFirst(ticks)
        return rest.contains(String(repeating: "`", count: ticks))
    }

    private static let newline = unichar(10)

    private static func lineEnd(_ s: NSString, from start: Int) -> Int {
        var i = start
        while i < s.length, s.character(at: i) != newline { i += 1 }
        return i
    }

    private static func block(_ s: NSString, _ start: Int, _ end: Int, add: (Int, Int, LiveStyleRun.Kind) -> Void) {
        var i = start
        while i < end, isSpace(s.character(at: i)) { i += 1 }
        let rest = s.substring(with: NSRange(location: i, length: end - i))
        let trimmed = rest.trimmingCharacters(in: .whitespaces)

        // Rule
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            add(i, end - i, .rule)
            return
        }
        // Heading
        if char(s, i) == "#" {
            var j = i
            while j < end, char(s, j) == "#" { j += 1 }
            let level = j - i
            if (1...6).contains(level), j < end, char(s, j) == " " {
                var k = j
                while k < end, char(s, k) == " " { k += 1 }
                add(start, k - start, .syntax)
                add(k, end - k, .heading(min(level, 3)))
                inline(s, k, end, add: add)
                return
            }
        }
        // Quote
        if char(s, i) == ">" {
            var k = i + 1
            if k < end, char(s, k) == " " { k += 1 }
            add(start, k - start, .syntax)
            add(k, end - k, .quote)
            inline(s, k, end, add: add)
            return
        }
        // Task / bullet
        if let marker = char(s, i), "-*+".contains(marker), char(s, i + 1) == " " {
            if char(s, i + 2) == "[", let mark = char(s, i + 3), " xX".contains(mark), char(s, i + 4) == "]",
               i + 5 == end || char(s, i + 5) == " " {
                add(i, 2, .syntax)
                add(i + 2, 3, .task(checked: mark != " "))
                var k = i + 5
                while k < end, char(s, k) == " " { k += 1 }
                if mark != " " { add(k, end - k, .done) }
                inline(s, k, end, add: add)
                return
            }
            add(i, 1, .bullet)
            inline(s, i + 2, end, add: add)
            return
        }
        inline(s, start, end, add: add)
    }

    // MARK: - inline

    private static func inline(_ s: NSString, _ start: Int, _ end: Int, add: (Int, Int, LiveStyleRun.Kind) -> Void) {
        var i = start
        while i < end {
            let c = char(s, i)
            if c == "`" {
                // A run of n backticks closes at the next run of exactly n.
                var n = 0
                while char(s, i + n) == "`" { n += 1 }
                let ticks = String(repeating: "`", count: n)
                var from = i + n
                var close: Int?
                while let j = find(ticks, in: s, from: from, to: end) {
                    if char(s, j + n) != "`" && char(s, j - 1) != "`" { close = j; break }
                    from = j + 1
                }
                if let j = close, j > i + n {
                    wrap(i, n, j, n, .code, add); i = j + n; continue
                }
                i += n; continue
            }
            if c == "*", char(s, i + 1) == "*", let j = find("**", in: s, from: i + 2, to: end), j > i + 2 {
                wrap(i, 2, j, 2, .bold, add); i = j + 2; continue
            }
            if c == "~", char(s, i + 1) == "~", let j = find("~~", in: s, from: i + 2, to: end), j > i + 2 {
                wrap(i, 2, j, 2, .strike, add); i = j + 2; continue
            }
            if c == "*", char(s, i + 1) != "*", char(s, i + 1) != " ",
               let j = find("*", in: s, from: i + 1, to: end), j > i + 1, char(s, j - 1) != " " {
                wrap(i, 1, j, 1, .italic, add); i = j + 1; continue
            }
            if c == "_", i == start || !isWordChar(s.character(at: i - 1)),
               let j = closingUnderscore(s, from: i + 1, to: end), j > i + 1 {
                wrap(i, 1, j, 1, .italic, add); i = j + 1; continue
            }
            if c == "[", let k = find("](", in: s, from: i + 1, to: end), k > i + 1,
               let m = find(")", in: s, from: k + 2, to: end) {
                let url = s.substring(with: NSRange(location: k + 2, length: m - k - 2))
                add(i, 1, .syntax)
                add(i + 1, k - i - 1, .link(url))
                add(k, m - k + 1, .syntax)
                i = m + 1; continue
            }
            i += 1
        }
    }

    private static func wrap(_ open: Int, _ openLength: Int, _ close: Int, _ closeLength: Int, _ kind: LiveStyleRun.Kind,
                             _ add: (Int, Int, LiveStyleRun.Kind) -> Void) {
        add(open, openLength, .syntax)
        add(open + openLength, close - open - openLength, kind)
        add(close, closeLength, .syntax)
    }

    private static func closingUnderscore(_ s: NSString, from: Int, to end: Int) -> Int? {
        var j = from
        while let found = find("_", in: s, from: j, to: end) {
            if found + 1 >= end || !isWordChar(s.character(at: found + 1)) { return found }
            j = found + 1
        }
        return nil
    }

    private static func find(_ needle: String, in s: NSString, from: Int, to end: Int) -> Int? {
        guard from < end else { return nil }
        let r = s.range(of: needle, options: .literal, range: NSRange(location: from, length: end - from))
        return r.location == NSNotFound ? nil : r.location
    }

    private static func char(_ s: NSString, _ i: Int) -> Character? {
        guard i >= 0, i < s.length, let scalar = Unicode.Scalar(s.character(at: i)) else { return nil }
        return Character(scalar)
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 }

    private static func isWordChar(_ c: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return true }   // surrogate half: part of a word
        return CharacterSet.alphanumerics.contains(scalar)
    }
}

private extension Int {
    /// `NSNotFound` (not found) → 0.
    var clampedToZero: Int { self == NSNotFound ? 0 : self }
}
