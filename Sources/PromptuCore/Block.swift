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
