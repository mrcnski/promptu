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
