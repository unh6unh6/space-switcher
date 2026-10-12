import Foundation

/// A pipe table in a memo's source (#21): header row, delimiter row (`|---|:-:|`), body rows.
struct MarkdownTable: Equatable {
    enum Alignment: Equatable { case left, center, right }

    struct Cell: Equatable {
        /// Trimmed cell source (inline Markdown still in it).
        let text: String
        /// Where `text` sits in the memo (UTF-16).
        let range: NSRange
    }

    /// Source lines of the whole table.
    let lines: ClosedRange<Int>
    let header: [Cell]
    let alignments: [Alignment]
    /// Padded (or cut) to the header's column count.
    let rows: [[Cell]]
}

/// Finds pipe tables, skipping code blocks. Pure.
enum MarkdownTables {
    static func find(in text: String) -> [MarkdownTable] {
        let s = text as NSString
        var lines: [NSRange] = []
        var start = 0
        while true {
            var end = start
            while end < s.length, s.character(at: end) != 10 { end += 1 }
            lines.append(NSRange(location: start, length: end - start))
            guard end < s.length else { break }
            start = end + 1
        }

        var tables: [MarkdownTable] = []
        var inFence = false
        var i = 0
        while i < lines.count {
            let line = s.substring(with: lines[i]).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inFence.toggle(); i += 1; continue }
            guard !inFence, i + 1 < lines.count, line.contains("|"),
                  let alignments = delimiter(s.substring(with: lines[i + 1])) else { i += 1; continue }
            let header = cells(s, lines[i])
            guard header.count == alignments.count else { i += 1; continue }

            var rows: [[MarkdownTable.Cell]] = []
            var last = i + 1
            var j = i + 2
            while j < lines.count {
                let row = s.substring(with: lines[j])
                guard row.contains("|"), !row.trimmingCharacters(in: .whitespaces).isEmpty else { break }
                var c = cells(s, lines[j])
                if c.count < header.count {
                    let end = NSMaxRange(lines[j])
                    c += Array(repeating: MarkdownTable.Cell(text: "", range: NSRange(location: end, length: 0)), count: header.count - c.count)
                }
                rows.append(Array(c.prefix(header.count)))
                last = j
                j += 1
            }
            tables.append(MarkdownTable(lines: i...last, header: header, alignments: alignments, rows: rows))
            i = last + 1
        }
        return tables
    }

    /// `|:---|:-:|--:|` → alignments; nil if the line isn't a delimiter row.
    private static func delimiter(_ line: String) -> [MarkdownTable.Alignment]? {
        var body = line.trimmingCharacters(in: .whitespaces)
        guard body.contains("-") else { return nil }
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        var result: [MarkdownTable.Alignment] = []
        for part in body.components(separatedBy: "|") {
            let p = part.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty, p.allSatisfy({ $0 == "-" || $0 == ":" }), p.contains("-") else { return nil }
            let left = p.hasPrefix(":"), right = p.hasSuffix(":")
            result.append(left && right ? .center : right ? .right : .left)
        }
        return result
    }

    /// Cells of a row: split on unescaped `|`, outer bars optional, each trimmed.
    private static func cells(_ s: NSString, _ line: NSRange) -> [MarkdownTable.Cell] {
        var bars: [Int] = []
        var i = line.location
        while i < NSMaxRange(line) {
            let c = s.character(at: i)
            if c == 92 { i += 2; continue }   // "\" escapes the next character
            if c == 124 { bars.append(i) }      // "|"
            i += 1
        }
        var bounds = [line.location - 1] + bars + [NSMaxRange(line)]
        // Outer bars: drop the empty stretch before the first / after the last.
        func isBlank(_ from: Int, _ to: Int) -> Bool {
            s.substring(with: NSRange(location: from + 1, length: max(0, to - from - 1))).trimmingCharacters(in: .whitespaces).isEmpty
        }
        if bounds.count > 2, isBlank(bounds[0], bounds[1]) { bounds.removeFirst() }
        if bounds.count > 2, isBlank(bounds[bounds.count - 2], bounds[bounds.count - 1]) { bounds.removeLast() }

        return zip(bounds, bounds.dropFirst()).map { from, to in
            var a = from + 1, b = to
            while a < b, s.character(at: a) == 32 || s.character(at: a) == 9 { a += 1 }
            while b > a, s.character(at: b - 1) == 32 || s.character(at: b - 1) == 9 { b -= 1 }
            let range = NSRange(location: a, length: b - a)
            return MarkdownTable.Cell(text: s.substring(with: range), range: range)
        }
    }
}
