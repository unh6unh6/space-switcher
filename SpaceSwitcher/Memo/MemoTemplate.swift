import Foundation

/// The text a desktop's first memo starts from (#36). Set in Settings → 메모; `{{name}}` becomes the
/// desktop's name and `{{date}}` the day the memo is started. Used once, when a desktop has no memo yet;
/// after that the memo is an ordinary memo. Pure.
enum MemoTemplate {
    static func render(_ template: String, name: String, date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
        return template
            .replacingOccurrences(of: "{{name}}", with: name)
            .replacingOccurrences(of: "{{date}}", with: day)
    }

    /// The filled-in template when the desktop has no memo yet; nil = start from the memo as it is.
    static func start(memo: String?, template: String, name: String, date: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard isBlank(memo), !isBlank(template) else { return nil }
        return render(template, name: name, date: date, timeZone: timeZone)
    }

    private static func isBlank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
