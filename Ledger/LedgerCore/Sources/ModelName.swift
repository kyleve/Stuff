import Foundation

/// A raw model identifier (e.g. `claude-opus-4-8-thinking-xhigh`,
/// `github_bugbot`, `non-max-composer-2.5-fast`) parsed into a friendly display
/// name plus a set of short badges (reasoning effort, speed, mode).
///
/// This is a best-effort heuristic tokenizer, not an exhaustive registry: it
/// recognizes the vendor/family words, version numbers, and effort/mode
/// suffixes seen in Cursor's model ids, and title-cases anything it doesn't
/// know — so a brand-new model still renders reasonably (`mistral-large-2` →
/// "Mistral Large 2") rather than as a raw slug.
public struct ModelName: Equatable, Sendable {
    /// The cleaned-up name, e.g. "Claude Opus 4.8".
    public var displayName: String
    /// Short badges in display order (mode, then effort, then speed), e.g.
    /// `["non-max", "xhigh"]`.
    public var badges: [String]

    public init(displayName: String, badges: [String]) {
        self.displayName = displayName
        self.badges = badges
    }

    /// Reasoning-effort tokens → badge label.
    private static let effortLabels: [String: String] = [
        "low": "low",
        "medium": "medium",
        "high": "high",
        "xhigh": "xhigh",
        "min": "min",
    ]

    /// Vendor/family words → their display casing. Anything absent is
    /// title-cased.
    private static let wordLabels: [String: String] = [
        "claude": "Claude",
        "opus": "Opus",
        "sonnet": "Sonnet",
        "haiku": "Haiku",
        "fable": "Fable",
        "gpt": "GPT",
        "codex": "Codex",
        "sol": "Sol",
        "grok": "Grok",
        "composer": "Composer",
        "gemini": "Gemini",
        "github": "GitHub",
        "bugbot": "Bugbot",
        "auto": "Auto",
    ]

    /// Hosting/qualifier words dropped from the display name.
    private static let droppedWords: Set<String> = ["cursor"]

    /// Parses `raw` into a display name and badges. An unrecognized or empty
    /// input falls back to the raw string as the display name.
    public static func parse(_ raw: String) -> ModelName {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ModelName(displayName: raw, badges: []) }

        var tokens = trimmed.lowercased().split { $0 == "-" || $0 == "_" }.map(String.init)

        var modeBadges: [String] = []
        // A leading "non-max" (→ ["non", "max"]) is a mode, not part of the name.
        if tokens.first == "non", tokens.count > 1, tokens[1] == "max" {
            modeBadges.append("non-max")
            tokens.removeFirst(2)
        }

        var effortBadges: [String] = []
        var speedBadges: [String] = []
        var nameTokens: [String] = []
        for token in tokens {
            if let effort = effortLabels[token] {
                effortBadges.append(effort)
            } else if token == "max" {
                modeBadges.append("max")
            } else if token == "fast" {
                speedBadges.append("fast")
            } else if token == "thinking" {
                continue // implied by the effort badge; omit from the name
            } else if droppedWords.contains(token) {
                continue
            } else {
                nameTokens.append(token)
            }
        }

        let displayName = formatName(nameTokens)
        let badges = modeBadges + effortBadges + speedBadges
        return ModelName(
            displayName: displayName.isEmpty ? trimmed : displayName,
            badges: badges,
        )
    }

    /// Joins name tokens, mapping known words and collapsing runs of integer
    /// tokens into a dotted version (`["4", "8"]` → `"4.8"`).
    private static func formatName(_ tokens: [String]) -> String {
        var parts: [String] = []
        var index = 0
        while index < tokens.count {
            if tokens[index].isAllDigits {
                var numbers: [String] = []
                while index < tokens.count, tokens[index].isAllDigits {
                    numbers.append(tokens[index])
                    index += 1
                }
                parts.append(numbers.joined(separator: "."))
            } else {
                parts.append(wordLabels[tokens[index]] ?? tokens[index].capitalized)
                index += 1
            }
        }
        return parts.joined(separator: " ")
    }
}

extension String {
    fileprivate var isAllDigits: Bool {
        !isEmpty && allSatisfy(\.isNumber)
    }
}
