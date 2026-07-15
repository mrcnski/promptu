/// Pure prompt-composition rules, mirroring Emacs promptu's compose core.
public enum Compose {
    public static let separator = "\n- "
    public static let negationPrefix = "don't "

    /// The template a block emits: its affirmative text, its explicit
    /// negative, or the affirmative text behind the negation prefix.
    public static func resolve(_ block: Block, negated: Bool) -> String {
        negated ? block.negative ?? negationPrefix + block.text : block.text
    }

    /// Replace each {name} in the template with its value.
    public static func substitute(_ template: String, values: [String: String]) -> String {
        values.reduce(template) { result, entry in
            result.replacingOccurrences(of: "{\(entry.key)}", with: entry.value)
        }
    }

    /// The block's placeholder names that appear as {name} in the template
    /// it emits when (not) negated.  Only these are worth prompting for.
    public static func activePlaceholders(_ block: Block, negated: Bool) -> [String] {
        let template = resolve(block, negated: negated)
        return (block.placeholders ?? []).filter { template.contains("{\($0)}") }
    }

    /// The separator's trailing line prefix: the text after its last
    /// newline, or "" for a separator without one.
    public static func linePrefix(_ separator: String = separator) -> String {
        guard let newline = separator.lastIndex(of: "\n") else { return "" }
        return String(separator[separator.index(after: newline)...])
    }

    /// Join entries with the separator.  When the separator contains a
    /// newline, the text after its last newline also prefixes the first
    /// entry, so the default "\n- " yields a fully bulleted list.
    public static func compose(_ entries: [String], separator: String = separator) -> String {
        guard !entries.isEmpty else { return "" }
        return linePrefix(separator) + entries.joined(separator: separator)
    }
}
