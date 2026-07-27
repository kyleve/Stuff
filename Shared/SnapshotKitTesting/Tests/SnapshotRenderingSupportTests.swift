@_spi(Testing) import SnapshotKitTesting
import TestHostSupport
import Testing
import UIKit

/// Regression guards for the settle loop's ending conditions. The budget bounds
/// *observed motion*, not proof-of-stability: a change-free loop that runs out
/// of budget before completing the three passes stability needs keeps going
/// until it can prove stability (CI reproduced the alternative — a static
/// screen failing as "still changing" on a starved runner), while content that
/// was actually seen changing still times out at the budget, and content that
/// can never be sampled ends `.starved` at the hard cap instead of hanging.
@MainActor
struct SnapshotRenderingSupportTests {
    /// A budget shorter than the quiet window means no run can prove stability
    /// inside it — the pre-fix loop always returned `.timedOut` here despite
    /// the content never once changing.
    @Test func staticContentSettlesPastABudgetTooShortToProveStability() async throws {
        let window = try hostWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        view.backgroundColor = .systemRed
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let outcome = await settleContent(view, minDuration: 0, maxDuration: 0.1)
        #expect(outcome == .settled)
    }

    @Test func contentObservedChangingStillTimesOutAtTheBudget() async throws {
        let window = try hostWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        // A monotone hue walk: every firing paints a color the loop has never
        // sampled, so each pass reads as a content change (alternating two
        // colors could alias with the sampling cadence).
        var hue: CGFloat = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
            MainActor.assumeIsolated {
                hue += 0.01
                view.backgroundColor = UIColor(
                    hue: hue.truncatingRemainder(dividingBy: 1),
                    saturation: 1,
                    brightness: 1,
                    alpha: 1,
                )
            }
        }
        defer { timer.invalidate() }

        let outcome = await settleContent(view, minDuration: 0, maxDuration: 0.15)
        #expect(outcome == .timedOut(budget: 0.15))
    }

    /// A zero-sized view yields no render sample, so no change is ever observed
    /// and no stability can ever be proven — the loop must give up at the hard
    /// cap as `.starved` rather than hang or misreport motion.
    @Test func unsampleableContentEndsStarvedAtTheHardCap() async throws {
        let window = try hostWindow()
        let view = UIView(frame: .zero)
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let outcome = await settleContent(view, minDuration: 0, maxDuration: 0.05)
        guard case let .starved(passes, cap) = outcome else {
            Issue.record("expected .starved, got \(outcome)")
            return
        }
        #expect(passes > 0)
        #expect(abs(cap - 0.2) < 0.001, "the hard cap is four budgets")
    }

    private func hostWindow() throws -> UIWindow {
        try waitFor { hostKeyWindow() != nil }
        return try #require(hostKeyWindow())
    }
}
