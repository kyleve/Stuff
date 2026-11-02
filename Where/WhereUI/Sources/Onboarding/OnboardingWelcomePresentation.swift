import LifecycleKit
import SwiftUI
import UIKit

/// Warms the destination beneath a welcome cover, then uses the startup reveal treatment.
struct OnboardingWelcomePresentation: ViewModifier {
    enum Destination: Equatable {
        case preparing
        case ready
        case failed

        init(phase: LifecycleRunner<some Sendable>.Phase) {
            switch phase {
                case .launching, .running, .awaitingGate: self = .preparing
                case .ready: self = .ready
                case .failed: self = .failed
            }
        }
    }

    let model: OnboardingWelcomeModel
    let destination: Destination
    let isPresentationVisible: Bool
    var onReveal: () -> Void = {}

    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        ZStack {
            content
                .accessibilityHidden(model.isPresented)
                .allowsHitTesting(!model.isPresented)

            if model.coversContent {
                OnboardingWelcomeView()
                    .accessibilityAddTraits(.isModal)
                    .transition(stylesheet.onboarding.welcome.reveal.transition)
                    .zIndex(1)
            }
        }
        .onChange(of: isPresentationVisible, initial: true) { _, visible in
            if !visible { model.pause() }
        }
        .onChange(of: destination, initial: true) { _, destination in
            if destination == .failed { model.cancel() }
        }
        .onChange(of: model.isPresented) { _, _ in
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        .onDisappear { model.pause() }
        .task(id: destination == .ready && isPresentationVisible && model.coversContent) {
            guard destination == .ready, isPresentationVisible, model.coversContent,
                  let deadline = model.startHold(
                      at: .now,
                      duration: stylesheet.onboarding.welcome.minimumDuration,
                  )
            else { return }
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                // ContinuousClock's sleep throws only for task cancellation.
                return
            }
            guard !Task.isCancelled, destination == .ready, isPresentationVisible else { return }
            withAnimation(
                stylesheet.onboarding.welcome.revealAnimation,
                completionCriteria: .removed,
            ) {
                _ = model.beginReveal(at: .now, deadline: deadline)
            } completion: {
                guard model.finishReveal(deadline: deadline) else { return }
                onReveal()
            }
        }
    }
}

#if DEBUG
    #Preview {
        let model = OnboardingWelcomeModel()
        model.present()
        return Color.clear
            .modifier(OnboardingWelcomePresentation(
                model: model,
                destination: .preparing,
                isPresentationVisible: true,
            ))
            .whereBroadwayRoot()
    }
#endif
