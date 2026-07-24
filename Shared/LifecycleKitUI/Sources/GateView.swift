import LifecycleKit
import SwiftUI

/// Registers the view for one gate *type* in a `LifecycleContainer`.
///
/// Registration is keyed by the gate's concrete type, which is how the
/// registry recovers the gate's `Value` statically: the content closure
/// receives the parked `LifecycleGateHandle` *and* the typed trunk value at
/// the gate, so a gate view is handed its dependencies rather than trusting
/// the environment to have been populated by an earlier step.
///
/// ```swift
/// gates: {
///     GateView(for: OnboardingGate.self) { handle, session in
///         OnboardingView(gate: handle, session: session)
///     }
/// }
/// ```
@MainActor
public struct GateView<G: LifecycleGate, Content: View> {
    let registration: GateRegistration

    public init(
        for _: G.Type,
        @ViewBuilder content: @escaping @MainActor (LifecycleGateHandle, G.Value) -> Content,
    ) {
        registration = GateRegistration(gateType: ObjectIdentifier(G.self)) { handle, value in
            // The engine parked a gate of exactly this type (the handle
            // carries it), so the erased trunk value is guaranteed to be the
            // gate's Value.
            AnyView(content(handle, value as! G.Value))
        }
    }
}

/// One erased gate-type → view entry, as `LifecycleContainer` stores it.
/// Built only by `GateView(for:content:)`, whose generic signature is where
/// the type recovery is checked.
@MainActor
public struct GateRegistration {
    let gateType: ObjectIdentifier
    let build: @MainActor (LifecycleGateHandle, any Sendable) -> AnyView
}

/// A gate parked but its type has no `GateView` registration — a
/// misconfiguration (the plan gates on something the UI can't render). The
/// container fails the gate's handle with this error, so the launch lands on
/// the failure surface (visible and named, though terminal) instead of an indefinite
/// splash that reads as progress; the behavior is identical in debug and
/// release.
public struct MissingGateViewError: Error, LocalizedError {
    /// The parked gate's identity, so the failure is diagnosable from the
    /// failure surface or a log line alone.
    public let gateID: AnyHashable

    public var errorDescription: String? {
        String(
            localized: "failure.gate.unregistered \(String(describing: gateID))",
            bundle: .module,
        )
    }
}

/// Result builder for `LifecycleContainer`'s `gates:` parameter, with
/// `if`/`if-else`/`for` support so registrations can be included
/// conditionally.
@resultBuilder
@MainActor
public enum GateRegistrationsBuilder {
    public static func buildExpression(
        _ gateView: GateView<some LifecycleGate, some View>,
    ) -> [GateRegistration] {
        [gateView.registration]
    }

    public static func buildBlock(_ registrations: [GateRegistration]...) -> [GateRegistration] {
        registrations.flatMap(\.self)
    }

    public static func buildOptional(_ registrations: [GateRegistration]?) -> [GateRegistration] {
        registrations ?? []
    }

    public static func buildEither(first registrations: [GateRegistration]) -> [GateRegistration] {
        registrations
    }

    public static func buildEither(second registrations: [GateRegistration]) -> [GateRegistration] {
        registrations
    }

    public static func buildArray(_ registrations: [[GateRegistration]]) -> [GateRegistration] {
        registrations.flatMap(\.self)
    }

    public static func buildLimitedAvailability(
        _ registrations: [GateRegistration],
    ) -> [GateRegistration] {
        registrations
    }
}
