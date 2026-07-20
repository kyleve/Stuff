import LifecycleKit
import Observation
import WhereCore

/// Mirrors a runner's detached-step failures into `WhereLog`, so a
/// fire-and-forget failure is observable in logs as well as on the runner's
/// `detachedFailures` state (the never-silently-swallow rule: a failure must
/// surface in logs, state, or both — the kit deliberately only records, and
/// no UI renders the diagnostics surface).
///
/// Today every detached launch step wraps a non-throwing `WhereSession`
/// method, so nothing can land here; this is the seam that keeps a *future*
/// throwing detached step from failing invisibly.
///
/// Installed by `WhereLaunch.makeLauncher`. Observation is UI-independent
/// (`withObservationTracking`, re-armed per change), so failures during a
/// headless background drive — where no view tree exists — are still logged.
/// The reporter is kept alive by its own observation chain and holds the
/// runner weakly, so it never extends the runner's lifetime; the chain ends
/// when the runner deallocates.
@MainActor
final class DetachedFailureReporter {
    private static let logger = WhereLog.root(WhereLaunchLog.self)

    /// How many entries of the runner's current `detachedFailures` array have
    /// been reported. The runner clears the array when a fresh attempt
    /// begins, so a shrink means "new attempt" and reporting restarts from
    /// zero — an entry is logged exactly once per appearance.
    private var reportedCount = 0

    /// Total failures reported over the reporter's lifetime (monotonic,
    /// unlike `reportedCount`, which resets with the runner's attempts).
    /// Lets tests pin the end-to-end observation plumbing without asserting
    /// on log output.
    private(set) var reportedTotal = 0

    /// Observe `runner.detachedFailures` for the runner's lifetime, logging
    /// new entries as they land.
    static func observe(_ runner: LifecycleRunner<some Sendable>) {
        DetachedFailureReporter().observe(runner)
    }

    /// Instance flavor of `observe(_:)`, so a test can keep the reporter and
    /// read `reportedTotal`.
    func observe(_ runner: LifecycleRunner<some Sendable>) {
        withObservationTracking {
            report(runner.detachedFailures)
        } onChange: { [weak runner] in
            Task { @MainActor [weak runner] in
                guard let runner else { return }
                self.observe(runner)
            }
        }
    }

    /// Log any not-yet-reported entries of `failures`, exactly once each,
    /// tolerating the runner's per-attempt resets. Returns the newly reported
    /// failures so tests can pin the exactly-once and reset semantics.
    @discardableResult
    func report(_ failures: [LifecycleFailure]) -> [LifecycleFailure] {
        if failures.count < reportedCount {
            reportedCount = 0
        }
        let new = Array(failures[reportedCount...])
        reportedCount = failures.count
        reportedTotal += new.count
        for failure in new {
            Self.logger(attachments: [.error(failure.error, name: "detached-error")]) {
                .detachedStepFailed(
                    stepID: String(describing: failure.stepID),
                    description: failure.error.localizedDescription,
                )
            }
        }
        return new
    }
}
