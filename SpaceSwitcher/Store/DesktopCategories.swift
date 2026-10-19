import Foundation

/// User-made categories (e.g. todo / inprogress / monitoring) and which desktop is in which (#35).
/// The switcher lists desktops grouped by category, in category order, uncategorized last; macOS's
/// own desktop order is never touched. One category per desktop, keyed by `Space.id`. Pure; persisted
/// as JSON in UserDefaults `desktopCategories`.
struct DesktopCategories: Codable, Equatable {
    struct Category: Codable, Equatable, Identifiable {
        let id: String
        var name: String
    }

    /// One header plus its desktops in the switcher. `title` nil = no header (nothing categorized yet).
    struct Group: Equatable {
        let title: String?
        let spaces: [Space]
    }

    static let maxNameLength = 20
    static let uncategorizedTitle = "미분류"
    static let didChange = Notification.Name("DesktopCategories.didChange")
    private static let key = "desktopCategories"

    private(set) var categories: [Category] = []
    /// `Space.id` → `Category.id`. Desktops that vanish keep theirs, like names do.
    private(set) var assignments: [String: String] = [:]

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

    /// The switcher's C key: none → first → … → last → none.
    mutating func cycle(_ spaceID: String) {
        guard !categories.isEmpty else { return }
        let current = category(for: spaceID).flatMap { c in categories.firstIndex { $0.id == c.id } }
        let next = current.map { $0 + 1 } ?? 0
        assign(categories.indices.contains(next) ? categories[next].id : nil, to: spaceID)
    }

    func groups(_ spaces: [Space]) -> [Group] {
        guard spaces.contains(where: { category(for: $0.id) != nil }) else { return [Group(title: nil, spaces: spaces)] }
        var result = categories.compactMap { c -> Group? in
            let members = spaces.filter { assignments[$0.id] == c.id }
            return members.isEmpty ? nil : Group(title: c.name, spaces: members)
        }
        let rest = spaces.filter { category(for: $0.id) == nil }
        if !rest.isEmpty { result.append(Group(title: Self.uncategorizedTitle, spaces: rest)) }
        return result
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

    private static func clean(_ name: String) -> String? {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        return trimmed.isEmpty ? nil : trimmed
    }
}
