/// The prompts already copied, newest first, each kept as its entry
/// list rather than as composed text: recalling one puts real entries
/// back into the Composition, still editable, removable and
/// reorderable. A port of promptu.el's history, minus the storage —
/// where the list is kept is the app's business, not this type's.
public struct History: Equatable, Sendable {
    /// How many prompts are kept; older ones fall off the end. Matches
    /// promptu.el's `promptu-history-max`.
    public static let limit = 50

    public private(set) var prompts: [[String]]

    /// Trims to `limit` on the way in, so a hand-edited or older
    /// oversized store can't grow the list past the cap.
    public init(_ prompts: [[String]] = []) {
        self.prompts = Array(prompts.prefix(Self.limit))
    }

    public var isEmpty: Bool { prompts.isEmpty }
    public var count: Int { prompts.count }

    /// Record a copied prompt at the front. Copying the same prompt
    /// again moves it rather than duplicating it: reuse is the common
    /// case, and it should not push the rest of the list out.
    public mutating func record(_ entries: [String]) {
        guard !entries.isEmpty else { return }
        prompts.removeAll { $0 == entries }
        prompts.insert(entries, at: 0)
        if prompts.count > Self.limit {
            prompts.removeLast(prompts.count - Self.limit)
        }
    }

    public mutating func remove(at index: Int) {
        guard prompts.indices.contains(index) else { return }
        prompts.remove(at: index)
    }

    public mutating func clear() { prompts.removeAll() }

    /// One line standing for a whole prompt, for a list row: the
    /// entries run together, and any newline inside a free-text entry
    /// is flattened. Single-line matters — a row that wrapped would
    /// resize the panel as the selection moved over it.
    public static func summary(_ entries: [String]) -> String {
        entries.joined(separator: " · ")
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
    }
}
