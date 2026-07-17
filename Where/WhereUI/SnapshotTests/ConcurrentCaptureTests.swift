import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Regression guard for `SnapshotCaptureLock`: the pipeline holds
/// process-global state (the safe-area swizzle + override globals, the
/// animations flag, the one host window) across its settle suspensions, so two
/// interleaved captures used to corrupt each other — the safe-area method
/// exchange is a parity toggle, and a second capture's swizzle un-swizzled the
/// first's (the Phase 13 parallel experiment produced 24+ spurious mismatches
/// this way). `renderSnapshotImage` now serializes captures through a FIFO
/// mutex, so concurrent calls must produce exactly the images serial calls do.
///
/// The probe view paints its safe area red over a green backdrop that ignores
/// it, so the rendered green strip *is* the effective top inset: capture A
/// (20pt override) must probe green at 10pt / red at 30pt, and capture B (zero
/// override) must probe red everywhere — pixels that shift if either capture
/// loses its override to the other (or to the device's real insets). A final
/// window-inset comparison catches a flipped swizzle parity leaking past the
/// captures.
@MainActor
struct ConcurrentCaptureTests {
    @Test func concurrentCapturesMatchSerialCaptures() async throws {
        try waitFor { hostKeyWindow() != nil }
        let windowInsetsBefore = hostKeyWindow()?.safeAreaInsets

        let serialInset = await expectations(for: captureProbeImage(topInset: 20))
        let serialZero = await expectations(for: captureProbeImage(topInset: 0))
        expectInsetCapture(serialInset)
        expectZeroInsetCapture(serialZero)

        // Two captures from one task group: both are MainActor jobs, so they
        // interleave at the pipeline's suspension points — exactly the
        // scheduling that corrupted captures before the lock serialized them.
        var concurrent: [CGFloat: ProbedCapture] = [:]
        await withTaskGroup(of: IndexedCapture.self) { group in
            for topInset: CGFloat in [20, 0] {
                group.addTask { @MainActor in
                    await IndexedCapture(
                        topInset: topInset,
                        capture: expectations(for: captureProbeImage(topInset: topInset)),
                    )
                }
            }
            for await result in group {
                concurrent[result.topInset] = result.capture
            }
        }

        let concurrentInset = try #require(concurrent[20])
        let concurrentZero = try #require(concurrent[0])
        expectInsetCapture(concurrentInset)
        expectZeroInsetCapture(concurrentZero)

        // A flipped swizzle parity would leave every UIView answering with the
        // (reset-to-zero) override globals instead of the native
        // implementation — visible as the host window's insets changing.
        #expect(hostKeyWindow()?.safeAreaInsets == windowInsetsBefore)
    }
}

/// A task-group result pairing a capture's probed pixels with the top inset it
/// was captured under.
private struct IndexedCapture {
    let topInset: CGFloat
    let capture: ProbedCapture
}

/// The probed pixels of one capture: a point inside the expected 20pt top
/// inset (10pt), a point just below it (30pt), and the center (50pt).
private struct ProbedCapture {
    let atTenPoints: PixelSample
    let atThirtyPoints: PixelSample
    let atCenter: PixelSample
}

/// Safe area painted red over a green backdrop ignoring it — the green strip's
/// height is the effective top safe-area inset.
private struct SafeAreaProbeView: View {
    var body: some View {
        ZStack {
            Color.green.ignoresSafeArea()
            Color.red
        }
    }
}

@MainActor
private func captureProbeImage(topInset: CGFloat) async -> UIImage {
    let host = UIHostingController(rootView: SafeAreaProbeView())
    host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    return await renderSnapshotImage(
        of: host,
        safeAreaInsets: UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0),
    )
}

private func expectations(for image: UIImage) -> ProbedCapture {
    ProbedCapture(
        atTenPoints: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.1)),
        atThirtyPoints: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.3)),
        atCenter: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5)),
    )
}

/// The 20pt-top-inset capture: green above the inset, red below it. The 30pt
/// probe discriminates against the device's real (larger) insets leaking in.
private func expectInsetCapture(
    _ capture: ProbedCapture,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(capture.atTenPoints.green > 0.5, sourceLocation: sourceLocation)
    #expect(capture.atTenPoints.red < 0.5, sourceLocation: sourceLocation)
    #expect(capture.atThirtyPoints.red > 0.5, sourceLocation: sourceLocation)
    #expect(capture.atThirtyPoints.green < 0.5, sourceLocation: sourceLocation)
    #expect(capture.atCenter.red > 0.5, sourceLocation: sourceLocation)
}

/// The zero-inset capture: red edge to edge — any green means it captured with
/// someone else's (or the device's) insets.
private func expectZeroInsetCapture(
    _ capture: ProbedCapture,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(capture.atTenPoints.red > 0.5, sourceLocation: sourceLocation)
    #expect(capture.atTenPoints.green < 0.5, sourceLocation: sourceLocation)
    #expect(capture.atThirtyPoints.red > 0.5, sourceLocation: sourceLocation)
    #expect(capture.atCenter.red > 0.5, sourceLocation: sourceLocation)
}
