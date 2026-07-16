import Foundation

/// Loads the block list shared with Emacs promptu.
public enum BlocksConfig {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/promptu/blocks.json")

    /// Contents seeded into blocks.json on first run: promptu.el's
    /// default block set (`promptu-default-blocks`), kept verbatim so
    /// the seeded file reads like a hand-written one.
    public static let defaultBlocksJSON = """
        [
          { "key": "t", "desc": "", "text": "{type a command}", "placeholders": ["type a command"] },
          { "key": "i", "desc": "investigate", "text": "investigate {link}", "placeholders": ["link"] },
          { "key": "b", "desc": "create branch", "text": "create a branch" },
          { "key": "r", "desc": "review changes", "text": "review your changes" },
          { "key": "c", "desc": "commit", "text": "commit" },
          { "key": "T", "desc": "add tests", "text": "add tests" },
          { "key": "p", "desc": "pause", "text": "pause" },
          { "key": "P", "desc": "push", "text": "push when done", "negative": "don't push" },
          { "key": "R", "desc": "create a PR", "text": "create a PR" },
          { "key": "C", "desc": "check CI", "text": "check CI" }
        ]
        """

    public static func load(_ url: URL = defaultURL) throws -> [Block] {
        try JSONDecoder().decode([Block].self, from: Data(contentsOf: url))
    }

    public static func save(_ blocks: [Block], to url: URL = defaultURL) throws {
        try Data(serialize(blocks).utf8).write(to: url, options: .atomic)
    }

    /// blocks.json text in the house style — one block per line, fields
    /// in schema order — so a saved file looks hand-written and diffs
    /// cleanly. Serializing the default blocks reproduces
    /// `defaultBlocksJSON` byte for byte.
    public static func serialize(_ blocks: [Block]) -> String {
        let lines = blocks.map { block in
            var fields = [
                "\"key\": \(quote(block.key))",
                "\"desc\": \(quote(block.desc))",
                "\"text\": \(quote(block.text))",
            ]
            if let negative = block.negative {
                fields.append("\"negative\": \(quote(negative))")
            }
            if let placeholders = block.placeholders {
                let items = placeholders.map(quote).joined(separator: ", ")
                fields.append("\"placeholders\": [\(items)]")
            }
            return "  { \(fields.joined(separator: ", ")) }"
        }
        return "[\n\(lines.joined(separator: ",\n"))\n]"
    }

    private static func quote(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Load the block list, first seeding the file with the default
    /// blocks when it doesn't exist. An existing file is never touched:
    /// a malformed one throws rather than being overwritten.
    public static func loadOrSeed(_ url: URL = defaultURL) throws -> [Block] {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(defaultBlocksJSON.utf8).write(to: url)
        }
        return try load(url)
    }
}
