import Foundation
import Testing
@testable import WhereUI

/// Covers `TypewriterSchedule`'s pause logic: a beat lands after sentence
/// terminators that end a sentence, but not after mid-token punctuation, and
/// `delay` picks the sentence pause only at those boundaries.
struct TypewriterScheduleTests {
    private static let base = Duration.milliseconds(10)
    private static let pause = Duration.milliseconds(200)

    @Test func pausesAfterASentenceTerminatorFollowedByASpace() {
        let characters = Array("Done. Next")
        // "Done." — the period is at index 4, followed by a space.
        #expect(TypewriterSchedule.pausesAfter(index: 4, in: characters))
    }

    @Test func pausesAfterATerminatorAtTheEndOfText() {
        let characters = Array("Hello.")
        #expect(TypewriterSchedule.pausesAfter(index: 5, in: characters))
    }

    @Test func doesNotPauseOnAMidNumberDot() {
        let characters = Array("3.14")
        // The dot at index 1 is followed by "1", not whitespace.
        #expect(!TypewriterSchedule.pausesAfter(index: 1, in: characters))
    }

    @Test func doesNotPauseOnANonTerminatorCharacter() {
        let characters = Array("Done. Next")
        #expect(!TypewriterSchedule.pausesAfter(index: 0, in: characters))
    }

    @Test func pausesAfterQuestionAndExclamationMarks() {
        let question = Array("Why? Because")
        let exclamation = Array("Go! Now")
        #expect(TypewriterSchedule.pausesAfter(index: 3, in: question))
        #expect(TypewriterSchedule.pausesAfter(index: 2, in: exclamation))
    }

    @Test func delayUsesTheSentencePauseOnlyAtABoundary() {
        let characters = Array("Hi. Go")
        let atBoundary = TypewriterSchedule.delay(
            afterIndex: 2,
            in: characters,
            characterDelay: Self.base,
            sentencePause: Self.pause,
        )
        let midText = TypewriterSchedule.delay(
            afterIndex: 0,
            in: characters,
            characterDelay: Self.base,
            sentencePause: Self.pause,
        )
        #expect(atBoundary == Self.pause)
        #expect(midText == Self.base)
    }
}
