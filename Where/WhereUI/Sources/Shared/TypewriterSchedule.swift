import Foundation

/// Pure pacing for a typewriter-style reveal: a base delay between characters,
/// with a longer beat after sentence-ending punctuation so streamed text lands
/// in natural sentences rather than a uniform crawl. Kept free of any view or
/// clock so the cadence is unit-tested deterministically, without waiting on
/// wall-clock time.
enum TypewriterSchedule {
    /// Punctuation that ends a sentence and earns a pause after it.
    static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]

    /// Whether the reveal should pause after the character at `index`: true only
    /// when it's a sentence terminator followed by whitespace or the end of the
    /// text. The "followed by whitespace" guard keeps mid-token dots quiet — a
    /// decimal like "3.14" or an abbreviation like "e.g.x" won't trigger a beat,
    /// while "Done. Next" does.
    static func pausesAfter(index: Int, in characters: [Character]) -> Bool {
        guard characters.indices.contains(index),
              sentenceTerminators.contains(characters[index])
        else {
            return false
        }
        let next = index + 1
        guard next < characters.count else { return true }
        return characters[next].isWhitespace
    }

    /// The delay to wait after revealing the character at `index` before
    /// revealing the next one: `sentencePause` at a sentence boundary, otherwise
    /// the base `characterDelay`.
    static func delay(
        afterIndex index: Int,
        in characters: [Character],
        characterDelay: Duration,
        sentencePause: Duration,
    ) -> Duration {
        pausesAfter(index: index, in: characters) ? sentencePause : characterDelay
    }
}
