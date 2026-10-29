import Foundation

/// User-made categories (e.g. todo / inprogress / monitoring) and which desktop is in which (#35).
/// The switcher lists desktops grouped by category, in category order, uncategorized last; inside a group
/// they follow the user's own order (#44: C and dragging move rows, and moving past a header is how a
/// desktop changes category). macOS's own desktop order is never touched. One category per desktop, keyed
/// by `Space.id`. Pure; persisted as JSON in UserDefaults `desktopCategories`.
struct DesktopCategories: Codable, Equatable {
    struct Category: Codable, Equatable, Identifiable {
        let id: String
        var name: String
    }

    /// One header plus its desktops in the switcher. `title` nil = no header (nothing categorized yet).
    /// `categoryID` nil = uncategorized.
    struct Group: Equatable {
        let title: String?
        var categoryID: String? = nil
        let spaces: [Space]
    }

    /// A line of the fully grouped list: a header (nil = 미분류) or a desktop. Rows move between these.
    enum Slot: Equatable {
        case header(String?)
        case space(String)
    }

    static let maxNameLength = 20
    static let uncategorizedTitle = "미분류"
    static let didChange = Notification.Name("DesktopCategories.didChange")
    private static let key = "desktopCategories"
    private static let enabledKey = "categoriesEnabled"
    private static let showsEmptyKey = "categoriesShowEmpty"

    private(set) var categories: [Category] = []
    /// `Space.id` → `Category.id`. Desktops that vanish keep theirs, like names do.
    private(set) var assignments: [String: String] = [:]
    /// `Space.id`s in the user's order (#44). Desktops not in it come last, in macOS order.
    private(set) var order: [String] = []

    init() {}

    /// Data saved before #44 has no order.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decode([Category].self, forKey: .categories)
        assignments = try c.decode([String: String].self, forKey: .assignments)
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
    }

    func category(for spaceID: String) -> Category? {
        assignments[spaceID].flatMap { id in categories.first { $0.id == id } }
    }

    /// False for a blank name or one already used.
    @discardableResult
    mutating func add(_ name: String, id: String = UUID().uuidString) -> Bool {
        guard let name = Self.clean(name), !categories.contains(where: { $0.name == name }) else { return false }
        categories.append(Category(id: id, name: name))
        return true
    }

    mutating func rename(_ id: String, to name: String) {
        guard let name = Self.clean(name), let i = categories.firstIndex(where: { $0.id == id }),
              !categories.contains(where: { $0.name == name && $0.id != id }) else { return }
        categories[i].name = name
    }

    /// Its desktops become uncategorized.
    mutating func remove(_ id: String) {
        categories.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
    }

    /// Moves a category up (−1) or down (+1) in the list, and so in the switcher.
    mutating func move(_ id: String, by delta: Int) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard categories.indices.contains(j) else { return }
        categories.swapAt(i, j)
    }

    /// nil = uncategorized. An unknown category is ignored.
    mutating func assign(_ categoryID: String?, to spaceID: String) {
        guard let categoryID else { assignments[spaceID] = nil; return }
        guard categories.contains(where: { $0.id == categoryID }) else { return }
        assignments[spaceID] = categoryID
    }

    /// `showsEmpty` (#43) keeps the headers of empty groups, 미분류 included, so rows can be moved under them.
    func groups(_ spaces: [Space], showsEmpty: Bool = false) -> [Group] {
        let spaces = sorted(spaces)
        guard !categories.isEmpty, showsEmpty || spaces.contains(where: { category(for: $0.id) != nil }) else {
            return [Group(title: nil, spaces: spaces)]
        }
        var result = categories.compactMap { c -> Group? in
            let members = spaces.filter { assignments[$0.id] == c.id }
            return members.isEmpty && !showsEmpty ? nil : Group(title: c.name, categoryID: c.id, spaces: members)
        }
        let rest = spaces.filter { category(for: $0.id) == nil }
        if !rest.isEmpty || showsEmpty { result.append(Group(title: Self.uncategorizedTitle, spaces: rest)) }
        return result
    }

    /// User order first, then the rest in macOS order.
    private func sorted(_ spaces: [Space]) -> [Space] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return spaces.enumerated().sorted { a, b in
            (rank[a.element.id] ?? order.count + a.offset, a.offset) < (rank[b.element.id] ?? order.count + b.offset, b.offset)
        }.map(\.element)
    }

    /// Every header (empty ones too) and desktop, top to bottom; no headers without categories.
    func slots(_ spaces: [Space]) -> [Slot] {
        groups(spaces, showsEmpty: true).flatMap { group in
            (group.title == nil ? [] : [Slot.header(group.categoryID)]) + group.spaces.map { Slot.space($0.id) }
        }
    }

    /// The switcher's C (#44): one line down, so past a header into that category; from the bottom back
    /// to the top of the first group.
    mutating func moveDown(_ id: String, among spaces: [Space]) {
        var lines = slots(spaces)
        guard let i = lines.firstIndex(of: .space(id)) else { return }
        lines.remove(at: i)
        let target = i < lines.count ? i + 1 : (lines.first.map { if case .header = $0 { return 1 } else { return 0 } } ?? 0)
        lines.insert(.space(id), at: target)
        apply(lines)
    }

    /// A drop (#44): just before or after `slot`. After a header = the top of that group.
    mutating func move(_ id: String, to slot: Slot, after: Bool, among spaces: [Space]) {
        guard slot != .space(id) else { return }
        var lines = slots(spaces)
        guard let i = lines.firstIndex(of: .space(id)) else { return }
        lines.remove(at: i)
        guard let j = lines.firstIndex(of: slot) else { return }
        lines.insert(.space(id), at: after ? j + 1 : j)
        apply(lines)
    }

    /// Reads categories and order back from the lines; desktops not among them keep their place in `order`.
    private mutating func apply(_ lines: [Slot]) {
        var category: String?
        var ids: [String] = []
        for line in lines {
            switch line {
            case .header(let c): category = c
            case .space(let id):
                ids.append(id)
                if !categories.isEmpty { assign(category, to: id) }
            }
        }
        let placed = Set(ids)
        order = ids + order.filter { !placed.contains($0) }
    }

    /// The switcher's row order.
    func ordered(_ spaces: [Space]) -> [Space] {
        groups(spaces).flatMap(\.spaces)
    }

    static func load(from defaults: UserDefaults = .standard) -> DesktopCategories {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(DesktopCategories.self, from: data) else { return DesktopCategories() }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// The category feature (#42), on by default. Off keeps the categories and assignments.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: enabledKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Empty categories in the switcher (#43), on by default.
    static func showsEmpty(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showsEmptyKey) == nil ? true : defaults.bool(forKey: showsEmptyKey)
    }

    static func setShowsEmpty(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: showsEmptyKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// What the switcher groups by: the stored categories, or none while the feature is off.
    static func active(from defaults: UserDefaults = .standard) -> DesktopCategories {
        isEnabled(in: defaults) ? load(from: defaults) : DesktopCategories()
    }

    private static func clean(_ name: String) -> String? {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        return trimmed.isEmpty ? nil : trimmed
    }
}
