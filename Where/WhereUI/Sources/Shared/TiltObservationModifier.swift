import SwiftUI

/// The lifecycle boundary between a visible surface and its motion sensor.
@MainActor
protocol TiltObserving: AnyObject {
    func start()
    func stop()
}

extension TiltProvider: TiltObserving {}

/// Runs a view-owned sensor only while its visible, active surface needs live reflections.
struct TiltObservationModifier<Tilt: TiltObserving>: ViewModifier {
    let tilt: Tilt
    let enabled: Bool

    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase
    @MotionIsStatic private var motionIsStatic

    private var shouldObserve: Bool {
        isVisible && enabled && !motionIsStatic && scenePhase == .active
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                updateObservation()
            }
            .onDisappear {
                isVisible = false
                tilt.stop()
            }
            .onChange(of: shouldObserve) { _, _ in updateObservation() }
    }

    private func updateObservation() {
        if shouldObserve {
            tilt.start()
        } else {
            tilt.stop()
        }
    }
}

extension View {
    func observesTilt(_ tilt: some TiltObserving, enabled: Bool) -> some View {
        modifier(TiltObservationModifier(tilt: tilt, enabled: enabled))
    }
}
