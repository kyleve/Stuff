import SwiftUI

/// Reveals `text` one character at a time, the way conversational AI tools
/// stream a reply — pausing a beat at sentence boundaries (see
/// `TypewriterSchedule`). Style it like any `Text`: font, color, and frame
/// modifiers applied to this view flow through to the rendered characters.
///
/// The full text is always exposed to assistive technologies (VoiceOver reads
/// the whole summary, not the partial reveal), and Reduce Motion shows it all
/// at once. Snapshot captures also render the final, fully revealed text — the
/// reveal's end state (see ``MotionIsStatic``). Restarts cleanly when `text`
/// changes.
struct TypewriterText: View {
    let text: String
    /// Base cadence between characters.
    var characterDelay: Duration = .milliseconds(18)
    /// Extra beat held at a sentence boundary.
    var sentencePause: Duration = .milliseconds(340)

    @MotionIsStatic private var motionIsStatic
    @State private var revealedCount = 0

    var body: some View {
        let characters = Array(text)
        Text(String(characters.prefix(revealedCount)))
            .accessibilityLabel(text)
            .task(id: text) { await reveal(characters) }
    }

    /// Walk the characters, revealing one per step and sleeping the scheduled
    /// delay between them. Static motion (Reduce Motion or snapshot capture —
    /// see ``MotionIsStatic``) and an empty string reveal instantly.
    /// Cancellation — the view went away or `text` changed — stops quietly; a
    /// new `text` restarts this task from zero.
    private func reveal(_ characters: [Character]) async {
        guard !motionIsStatic else {
            revealedCount = characters.count
            return
        }
        revealedCount = 0
        for index in characters.indices {
            revealedCount = index + 1
            guard index + 1 < characters.count else { break }
            do {
                try await Task.sleep(
                    for: TypewriterSchedule.delay(
                        afterIndex: index,
                        in: characters,
                        characterDelay: characterDelay,
                        sentencePause: sentencePause,
                    ),
                )
            } catch {
                return
            }
        }
    }
}

#if DEBUG
    #Preview {
        TypewriterText(
            text: "You spent the morning in California. In the early evening you traveled to New York, where the most recent readings place you.",
        )
        .font(.body)
        .padding()
    }
#endif
