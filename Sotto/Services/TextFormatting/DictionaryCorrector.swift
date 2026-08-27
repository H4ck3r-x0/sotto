import Foundation

/// Guaranteed corrections for names and jargon the speech model gets wrong.
///
/// Reads a plain-text file the user can edit directly. Two line formats:
///
///     Xcode                        ← canonical term: any case/spacing/hyphen
///                                    variant ("x code", "xcode")
///                                    is rewritten to exactly this
///     jason → JSON                 ← explicit replacement ("=" also works)
///
/// Matching is case-insensitive, whole-word, longest-pattern-first so that
/// e.g. a "java" rule can never corrupt "JavaScript".
struct DictionaryCorrector {
    struct Rule {
        let pattern: NSRegularExpression
        let replacement: String
        let length: Int
    }

    static let fileURL: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sotto", isDirectory: true)
        return directory.appendingPathComponent("dictionary.txt")
    }()

    private static let template = """
    # Sotto dictionary — one rule per line.
    #
    #   Xcode                ← canonical term: "x code", "xcode", …
    #                          all become exactly "Xcode"
    #   jason → JSON         ← explicit replacement ("=" also works)
    #
    # Matching is case-insensitive and whole-word. Lines starting with # are ignored.

    """

    let rules: [Rule]

    init() {
        Self.createFileIfMissing()
        let content = (try? String(contentsOf: Self.fileURL, encoding: .utf8)) ?? ""
        rules = Self.parse(content).sorted { $0.length > $1.length }
    }

    static func createFileIfMissing() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? template.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func correct(_ text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.pattern.stringByReplacingMatches(
                in: result, range: range, withTemplate: rule.replacement
            )
        }
        return result
    }

    private static func parse(_ content: String) -> [Rule] {
        content.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

            let spoken: String
            let replacement: String
            if let separator = line.range(of: "→") ?? line.range(of: "=") {
                spoken = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                replacement = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                spoken = line
                replacement = line
            }
            guard !spoken.isEmpty, !replacement.isEmpty else { return nil }

            // Canonical terms tolerate flexible spacing/hyphens between words
            // and inside joined words: "claude code" also matches "claudecode".
            let tokens = spoken.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let body = tokens.joined(separator: #"[\s\-]*"#)
            guard let pattern = try? NSRegularExpression(
                pattern: #"\b"# + body + #"\b"#,
                options: [.caseInsensitive]
            ) else { return nil }

            return Rule(
                pattern: pattern,
                replacement: NSRegularExpression.escapedTemplate(for: replacement),
                length: spoken.count
            )
        }
    }
}
