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
    /// Exercise UIKit's compositing and downsampling before sRGB normalization.
    /// The scripted-context tests below bypass that path, so they cannot catch
    /// changes lost while converting a colored or translucent hierarchy.
    @Test(arguments: HierarchyChange.allCases)
    func hierarchyChangesSurviveSampling(change: HierarchyChange) async throws {
        let window = try hostWindow()
        let view = ChangingHierarchyView(change: change)
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let outcome = await settleContent(view, named: #function, minDuration: 0, maxDuration: 0.25)

        #expect(outcome == .timedOut(budget: 0.25))
        #expect(view.sampleCount >= 2)
    }

    @Test(arguments: [SnapshotSettleMechanism.pixel, .both])
    func oneUnitRenderNoiseSettlesWithoutShorteningTheFloor(
        mechanism: SnapshotSettleMechanism,
    ) async throws {
        let window = try hostWindow()
        let view = ScriptedSettleView { context, rect, pass in
            context.setFillColor(gray: CGFloat(200 + pass % 2) / 255, alpha: 1)
            context.fill(rect)
        }
        window.addSubview(view)
        defer { view.removeFromSuperview() }
        let clock = ContinuousClock()
        let start = clock.now

        let outcome = await settleContent(view, named: #function, mechanism: mechanism)

        #expect(outcome == .settled)
        #expect(start.duration(to: clock.now) >= .milliseconds(250))
        #expect(view.sampleCount >= 3)
    }

    @Test func twoUnitRenderChangesStillTimeOut() async throws {
        let window = try hostWindow()
        let view = ScriptedSettleView { context, rect, pass in
            context.setFillColor(gray: CGFloat(200 + (pass % 2) * 2) / 255, alpha: 1)
            context.fill(rect)
        }
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let outcome = await settleContent(view, named: #function, minDuration: 0, maxDuration: 0.15)

        #expect(outcome == .timedOut(budget: 0.15))
        #expect(view.sampleCount >= 2)
    }

    @Test func cancellationAfterTheFirstSampleEndsSettling() async throws {
        let window = try hostWindow()
        let view = ScriptedSettleView { context, rect, _ in
            context.setFillColor(gray: 0.5, alpha: 1)
            context.fill(rect)
            withUnsafeCurrentTask { $0?.cancel() }
        }
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let task = Task { await settleContent(view, named: #function) }
        #expect(await task.value == .cancelled)
        #expect(view.sampleCount == 1)
    }

    /// A budget shorter than the quiet window means no run can prove stability
    /// inside it — the pre-fix loop always returned `.timedOut` here despite
    /// the content never once changing.
    @Test func staticContentSettlesPastABudgetTooShortToProveStability() async throws {
        let window = try hostWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        view.backgroundColor = .systemRed
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let outcome = await settleContent(view, named: #function, minDuration: 0, maxDuration: 0.1)
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

        let outcome = await settleContent(view, named: #function, minDuration: 0, maxDuration: 0.15)
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

        let outcome = await settleContent(view, named: #function, minDuration: 0, maxDuration: 0.05)
        guard case let .starved(passes, cap) = outcome else {
            Issue.record("expected .starved, got \(outcome)")
            return
        }
        #expect(passes > 0)
        #expect(abs(cap - 0.2) < 0.001, "the hard cap is four budgets")
    }

    /// The pre-capture animation drain must stay effectively free.
    ///
    /// It used to run a zero-duration `UIView.animate` and pump the run loop
    /// until its completion fired, with a 1-second timeout as the backstop. The
    /// completion never fired, so every capture paid the whole second — 55% of a
    /// capture, and about a third of the suite — waiting for a callback that
    /// never arrived. Nothing but wall time caught that, and nothing but wall
    /// time would catch its return: a reinstated pump keeps every reference
    /// passing and just makes the suite slow again. Hence a duration assertion,
    /// with a bound loose enough to survive a loaded machine and still an order
    /// of magnitude under the budget it replaced.
    @Test func drainingAnimationsDoesNotWaitOnACallback() {
        let clock = ContinuousClock()
        let began = clock.now
        for _ in 0 ..< 5 {
            drainInFlightAnimations()
        }
        let elapsed = began.duration(to: clock.now)
        #expect(
            elapsed < .milliseconds(250),
            "five drains took \(elapsed); the pump this replaced cost 1s each",
        )
    }

    /// The drain's actual job: commit the pending transaction so anything waiting
    /// on it has run before the capture.
    @Test func drainingAnimationsFlushesPendingCommitWork() throws {
        let window = try hostWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        view.setNeedsLayout()
        drainInFlightAnimations()
        #expect(!view.layer.needsLayout(), "a commit should have laid the layer out")
    }

    private func hostWindow() throws -> UIWindow {
        try waitFor { hostKeyWindow() != nil }
        return try #require(hostKeyWindow())
    }
}

enum HierarchyChange: CaseIterable {
    case color
    case translucentColor
    case cumulativeFade
    case lastSamplePixel
    case clippedColorNeighbor
    case translucentClippedColorNeighbor
}

/// Change real layers, then use UIKit's actual hierarchy renderer. Updating at
/// the sample boundary avoids a timer racing or aliasing with the sampler.
@MainActor
private final class ChangingHierarchyView: UIView {
    private let change: HierarchyChange
    private let patch = UIView()
    private(set) var sampleCount = 0

    init(change: HierarchyChange) {
        self.change = change
        super.init(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        backgroundColor = UIColor(white: 0.8, alpha: 1)
        // Four points occupy one pixel in the 0.25-scale settle sample. Put it
        // at the far end to guard against comparing only a prefix or most pixels.
        patch.frame = change == .lastSamplePixel
            ? CGRect(x: 60, y: 60, width: 4, height: 4)
            : bounds
        if change == .clippedColorNeighbor || change == .translucentClippedColorNeighbor {
            // Both colors contribute to one downsampled pixel. Converting and
            // clipping wide color before versus after averaging can hide the
            // small green change beside saturated P3 red.
            backgroundColor = UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
            patch.frame = CGRect(x: 60.5, y: 60, width: 1, height: 4)
        }
        addSubview(patch)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool {
        sampleCount += 1
        switch change {
            case .color, .translucentColor:
                patch.backgroundColor = UIColor(
                    displayP3Red: 0.8,
                    green: sampleCount.isMultiple(of: 2) ? 0.2 : 0.4,
                    blue: 0.1,
                    alpha: change == .translucentColor ? 0.35 : 1,
                )
            case .cumulativeFade:
                patch.backgroundColor = UIColor(
                    white: CGFloat(180 + min(sampleCount, 60)) / 255,
                    alpha: 1,
                )
            case .lastSamplePixel:
                patch.backgroundColor = sampleCount.isMultiple(of: 2) ? .black : .white
            case .clippedColorNeighbor, .translucentClippedColorNeighbor:
                patch.backgroundColor = UIColor(
                    red: 0,
                    green: sampleCount.isMultiple(of: 2) ? 0.1 : 0.2,
                    blue: 0,
                    alpha: change == .translucentClippedColorNeighbor ? 0.5 : 1,
                )
        }
        return super.drawHierarchy(in: rect, afterScreenUpdates: afterUpdates)
    }
}
