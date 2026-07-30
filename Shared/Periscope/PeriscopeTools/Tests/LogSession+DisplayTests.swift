import Foundation
import PeriscopeCore
@testable import PeriscopeTools
import Testing

/// Covers the session-picker label: what it says when the session named its
/// build, and what it omits when it couldn't.
struct LogSessionDisplayTests {
    private let startedAt = Date(timeIntervalSince1970: 1_753_700_000)

    @Test func namesTheDateAndVersionWhenTheSessionKnowsNothingElse() {
        let label = makeSession(startedAt: startedAt).displayLabel
        #expect(label.contains("v1.0 (42)"))
        #expect(label.contains(startedAt.formatted(date: .abbreviated, time: .shortened)))
    }

    @Test func namesTheCommitAndOptimizationLevelWhenTheSessionCarriesThem() {
        let label = makeSession(
            startedAt: startedAt,
            attributes: [
                .commit: "a18a9309c5d6",
                .commitStatus: "clean",
                .optimizationLevel: "-O",
            ],
        ).displayLabel
        #expect(label.hasSuffix("v1.0 (42) · a18a9309c5d6 · -O"))
    }

    @Test func marksACommitBuiltFromADirtyTree() {
        let label = makeSession(
            startedAt: startedAt,
            attributes: [.commit: "a18a9309c5d6", .commitStatus: "dirty"],
        ).displayLabel
        #expect(label.hasSuffix("a18a9309c5d6 (dirty)"))
    }

    /// A session that didn't state its commit status must not read as a clean
    /// tree — the label says nothing rather than implying reproducibility.
    @Test func doesNotClaimACleanTreeWhenTheStatusIsUnstated() {
        let label = makeSession(startedAt: startedAt, attributes: [.commit: "a18a9309c5d6"])
            .displayLabel
        #expect(label.hasSuffix("a18a9309c5d6"))
        #expect(!label.contains("dirty"))
    }

    @Test func ignoresACommitStatusItDoesNotRecognize() {
        let label = makeSession(
            startedAt: startedAt,
            attributes: [.commit: "a18a9309c5d6", .commitStatus: "probably-fine"],
        ).displayLabel
        #expect(label.hasSuffix("a18a9309c5d6"))
    }

    /// The status is only ever a suffix on a commit, so a session that reported
    /// one without a commit contributes nothing rather than a bare "(dirty)".
    @Test func saysNothingAboutAStatusWithoutACommit() {
        let label = makeSession(startedAt: startedAt, attributes: [.commitStatus: "dirty"])
            .displayLabel
        #expect(label.hasSuffix("v1.0 (42)"))
    }
}
