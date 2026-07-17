import Foundation

/// One building block, as read from blocks.json.
///
/// Mirrors the block plist schema of Emacs promptu's `promptu-blocks`.
public struct Block: Codable, Hashable, Identifiable, Sendable {
    public var key: String
    public var desc: String
    public var text: String
    public var negative: String?
    public var placeholders: [String]?

    public var id: String { key }

    public init(
        key: String, desc: String, text: String,
        negative: String? = nil, placeholders: [String]? = nil
    ) {
        self.key = key
        self.desc = desc
        self.text = text
        self.negative = negative
        self.placeholders = placeholders
    }
}

extension [Block] {
    /// The list with the block for `key` moved into `target`'s slot,
    /// shifting the blocks between them — one step of a live drag
    /// reorder. Unchanged when either key is missing or they name the
    /// same block.
    public func moving(_ key: String, over target: String) -> [Block] {
        guard let from = firstIndex(where: { $0.key == key }),
            let to = firstIndex(where: { $0.key == target }),
            from != to
        else { return self }
        var moved = self
        moved.insert(moved.remove(at: from), at: to)
        return moved
    }
}
