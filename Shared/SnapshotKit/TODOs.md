# SnapshotKit todos

## Usage
- Tag issues with conventional commit semantics: feat, fix, refactor, perf, test, docs
	- Eg "- fix: Rebuild case content per configuration"
- Nest tasks that depend on other tasks.
- Don't delete completed tasks, move them to the "Completed issues" section at the bottom.

# Open issues

## P1s (Should do)
- fix: A case's content and captured models are instantiated once and shared across every configuration — `SnapshotCase.init` (`Sources/SnapshotCase.swift`) evaluates `content()` once into an `AnyView`, and the runner re-hosts that same value (and re-runs the same `onReadyToSnapshot` closure) for each of up to 10+ configurations (`SnapshotKitTesting`'s `AssertSnapshots.swift`). `@State` re-initializes per hosting, but reference-type models captured in the builder (`PreviewSupport.loadedYearReportModel()` and every provider like it) are shared: a `.task` side effect or a pre-capture hook mutation persists into all later configurations of the case — deterministic but surprising (variant N's reference bakes in variant 1's mutations), and nothing in the `SnapshotCase`/hook docs says content is built once per case rather than per configuration. Fix: store the content closure and rebuild per configuration (isolating state), or document the one-instance-per-case contract loudly on `SnapshotCase` and the hook. (From the July 2026 snapshot-testing PR review.)

# Completed issues
