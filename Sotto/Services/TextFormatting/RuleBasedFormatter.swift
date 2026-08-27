import Foundation

/// Deterministic post-transcription cleanup. No models, no surprises —
/// every rule is individually toggleable in Settings.
struct RuleBasedFormatter {
    var removeFillers = UserDefaults.standard.object(forKey: "format.removeFillers") as? Bool ?? true
    var capitalizeSentences = UserDefaults.standard.object(forKey: "format.capitalize") as? Bool ?? true
    var terminalPunctuation = UserDefaults.standard.bool(forKey: "format.terminalPunctuation")

    private static let fillerPattern = try! NSRegularExpression(
        // Standalone fillers, absorbing one adjacent comma so
        // "I think, um, we should" → "I think we should".
        pattern: #"(?:,\s*)?\b(?:u+m+|u+h+|erm+|hm+m*|mhm+)\b(?:,)?"#,
        options: [.caseInsensitive]
    )

    func format(_ text: String) -> String {
        var result = text

        if removeFillers {
            let range = NSRange(result.startIndex..., in: result)
            result = Self.fillerPattern.stringByReplacingMatches(
                in: result, range: range, withTemplate: ""
            )
        }

        // Normalize whitespace artifacts left by removals.
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        if capitalizeSentences {
            result = capitalizingSentenceStarts(result)
        }

        if terminalPunctuation, let last = result.last, !"?!.:,;…".contains(last) {
            result += "."
        }

        return result
    }

    private func capitalizingSentenceStarts(_ text: String) -> String {
        var characters = Array(text)
        var atSentenceStart = true
        for index in characters.indices {
            let char = characters[index]
            if atSentenceStart, char.isLetter {
                characters[index] = Character(char.uppercased())
                atSentenceStart = false
            } else if ".!?".contains(char) {
                atSentenceStart = true
            } else if !char.isWhitespace {
                atSentenceStart = false
            }
        }
        return String(characters)
    }
}
