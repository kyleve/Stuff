import SnapshotKit
import SwiftUI
import TestHostSupport
import Testing
import UIKit
import WhereCore
@testable import WhereUI

@MainActor
struct TiltObservationModifierTests {
    @Test func followsMountedThemeCaptureAndSceneChanges() throws {
        let tilt = RecordingTiltObserver()
        func content(theme: WhereTheme, phase: ScenePhase, isCapturingSnapshot: Bool) -> some View {
            TiltObservationProbe(tilt: tilt)
                .whereBroadwayRoot(theme: theme)
                .environment(\.scenePhase, phase)
                .environment(\.isCapturingSnapshot, isCapturingSnapshot)
        }
        let host = UIHostingController(rootView: content(
            theme: .standard,
            phase: .active,
            isCapturingSnapshot: false,
        ))
        try show(host) { _ in
            try waitFor { tilt.isRunning }
            host.rootView = content(theme: .alternate, phase: .active, isCapturingSnapshot: false)
            try waitFor { !tilt.isRunning }
            host.rootView = content(theme: .standard, phase: .active, isCapturingSnapshot: false)
            try waitFor { tilt.isRunning }
            host.rootView = content(theme: .standard, phase: .active, isCapturingSnapshot: true)
            try waitFor { !tilt.isRunning }
            host.rootView = content(theme: .standard, phase: .active, isCapturingSnapshot: false)
            try waitFor { tilt.isRunning }
            host.rootView = content(
                theme: .standard,
                phase: .background,
                isCapturingSnapshot: false,
            )
            try waitFor { !tilt.isRunning }
            host.rootView = content(theme: .standard, phase: .active, isCapturingSnapshot: false)
            try waitFor { tilt.isRunning }
        }
        try waitFor { !tilt.isRunning }
    }
}

private struct TiltObservationProbe: View {
    let tilt: RecordingTiltObserver
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Color.clear.observesTilt(tilt, enabled: stylesheet.card.regular.surface.usesReflection)
    }
}

@MainActor
private final class RecordingTiltObserver: TiltObserving {
    private(set) var isRunning = false

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }
}
