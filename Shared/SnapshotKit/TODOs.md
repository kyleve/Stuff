# SnapshotKit todos

## Usage
- Tag issues with conventional commit semantics: feat, fix, refactor, perf, test, docs
	- Eg "- fix: Rebuild case content per configuration"
- Nest tasks that depend on other tasks.
- Don't delete completed tasks, move them to the "Completed issues" section at the bottom.

# Open issues

## P1s (Should do)
- fix: A case's captured models are shared across every configuration, because the *runner* hoists the content out of the loop. `@State` re-initializes per hosting, but reference-type models captured in the builder (`PreviewSupport.loadedYearReportModel()` and every provider like it) are shared: a `.task` side effect or a pre-capture hook mutation persists into all later configurations of the case — deterministic but surprising (variant N's reference bakes in variant 1's mutations). **Half fixed** (2026-08-02): `SnapshotCase` is no longer the culprit — it now stores a `contentFactory` and rebuilds on each `content` access (`Sources/SnapshotCase.swift:47-69`), pinned by `SnapshotCaseTests.swift:51-65`. What remains is one call site: `SnapshotKitTesting`'s provider overload reads `snapshotCase.content` **once** and passes that single `AnyView` into the inline overload (`SnapshotKitTesting/Sources/AssertSnapshots.swift:44-45`), which re-hosts the same value for every configuration (`:104-105`). Fix: pass the factory (or re-read `content` per configuration) there. (From the July 2026 snapshot-testing PR review.)

# Completed issues
