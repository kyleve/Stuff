# SnapshotKit todos

## Usage
- Tag issues with conventional commit semantics: feat, fix, refactor, perf, test, docs
	- Eg "- fix: Rebuild case content per configuration"
- Nest tasks that depend on other tasks.
- Don't delete completed tasks, move them to the "Completed issues" section at the bottom.

# Open issues

## P1s (Should do)
- fix: A case's content and captured models are instantiated once and shared across every configuration. `SnapshotCase.content` is a lazy `AnyView` accessor (`Sources/SnapshotCase.swift:49-51`), but the runner reads it **once** per case (`SnapshotKitTesting/Sources/AssertSnapshots.swift:44-45`) and re-hosts that same value — and re-runs the same `onReadyToSnapshot` closure — for each of up to 10+ configurations (`:104-105`). `@State` re-initializes per hosting, but reference-type models captured in the builder (`PreviewSupport.loadedYearReportModel()` and every provider like it) are shared: a `.task` side effect or a pre-capture hook mutation persists into all later configurations of the case — deterministic but surprising (variant N's reference bakes in variant 1's mutations). **The docs now make it worse rather than merely silent:** `SnapshotCase.swift:47-48` states "Each access creates an independent view value for its configuration", which is true of the accessor and false of how the runner uses it, so a test author reading the type is actively told the isolation exists. Fix: rebuild per configuration by accessing `content` inside the configuration loop (isolating state), or correct that sentence and document the one-instance-per-case contract loudly on `SnapshotCase` and the hook. (From the July 2026 snapshot-testing PR review; re-verified and doc contradiction found 2026-08-09)

# Completed issues
