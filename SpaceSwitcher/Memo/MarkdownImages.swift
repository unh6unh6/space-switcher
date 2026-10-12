import CoreGraphics
import Foundation

/// An image on its own line: `![alt](source)` (#21). Inline images inside text are left as text.
struct MarkdownImage: Equatable {
    let line: Int
    let alt: String
    let source: String
}

/// Finding, resolving, sizing and naming memo images. Pure.
enum MarkdownImages {
    static let maxHeight: CGFloat = 240
    static let folder = "images"

    static func find(in text: String) -> [MarkdownImage] {
        var result: [MarkdownImage] = []
        var inFence = false
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence, let image = parse(trimmed) else { continue }
            result.append(MarkdownImage(line: index, alt: image.alt, source: image.source))
        }
        return result
    }

    /// `![alt](source)`, `![alt](<source with spaces>)`, optional `"title"` after the source.
    static func parse(_ trimmed: String) -> (alt: String, source: String)? {
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")"), let close = trimmed.range(of: "](") else { return nil }
        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
        var inside = String(trimmed[close.upperBound..<trimmed.index(before: trimmed.endIndex)]).trimmingCharacters(in: .whitespaces)
        if inside.hasPrefix("<"), let end = inside.firstIndex(of: ">") {
            inside = String(inside[inside.index(after: inside.startIndex)..<end])
        } else if let space = inside.firstIndex(of: " ") {
            inside = String(inside[..<space])   // drop a "title"
        }
        guard !inside.isEmpty, !alt.contains("]") else { return nil }
        return (alt, inside)
    }

    /// Relative sources are relative to the memo folder, as in Obsidian and other editors.
    static func resolve(_ source: String, base: URL?) -> URL? {
        if source.hasPrefix("http://") || source.hasPrefix("https://") { return URL(string: source) }
        if source.hasPrefix("file://") { return URL(string: source) }
        let path = source.removingPercentEncoding ?? source
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("~/") { return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2))) }
        return base?.appendingPathComponent(path)
    }

    /// Fit the width, at most `maxHeight` tall, never larger than the image itself.
    static func displaySize(natural: CGSize, width: CGFloat) -> CGSize {
        guard natural.width > 0, natural.height > 0 else { return .zero }
        let scale = min(1, width / natural.width, maxHeight / natural.height)
        return CGSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
    }

    /// A free name in `images/`: the dropped file's own name, or a timestamp for pasted image data.
    static func fileName(original: String?, taken: Set<String>, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let name: String
        if let original, !original.isEmpty {
            name = original
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = "yyyyMMdd-HHmmss"
            name = "image-\(f.string(from: date)).png"
        }
        guard taken.contains(name) else { return name }
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        var n = 2
        while taken.contains("\(stem)-\(n)\(ext.isEmpty ? "" : "." + ext)") { n += 1 }
        return "\(stem)-\(n)\(ext.isEmpty ? "" : "." + ext)"
    }

    static func markdown(path: String) -> String {
        path.contains(" ") ? "![](<\(path)>)" : "![](\(path))"
    }
}
