import PortholeRuntime
import SwiftUI

extension View {
    /// A visible application seam. Developer surfaces deliberately do not apply this modifier.
    func portholeScreen(
        _ title: String,
        source: PortholeSourceLocation,
        roots: [any Sendable],
        when enabled: Bool = true,
        capture: @escaping @MainActor () throws -> PortholeValue,
    ) -> some View {
        modifier(WherePortholeScreen(
            title: title,
            source: source,
            roots: roots,
            enabled: enabled,
            capture: capture,
        ))
    }
}

private struct WherePortholeScreen: ViewModifier {
    let title: String
    let source: PortholeSourceLocation
    let roots: [any Sendable]
    let enabled: Bool
    let capture: @MainActor () throws -> PortholeValue
    @Environment(WhereModel.self) private var model: WhereModel?
    @Environment(\.portholeContextDepth) private var depth
    @State private var identity = UUID()

    private struct RegistrationIdentity: Equatable {
        let scope: ObjectIdentifier?
        let depth: Int
        let title: String
        let source: PortholeSourceLocation
        let enabled: Bool
    }

    func body(content: Content) -> some View {
        let registration = RegistrationIdentity(
            scope: model?.activeScope.map(ObjectIdentifier.init),
            depth: depth,
            title: title,
            source: source,
            enabled: enabled,
        )
        content.onAppear { register() }
            .onChange(of: registration) { _, _ in register() }
            .onDisappear { model?.porthole.leave(identity) }
            .environment(\.portholeContextDepth, depth + (enabled ? 1 : 0))
    }

    private func register() {
        guard enabled else { model?.porthole.leave(identity); return }
        model?.porthole.enter(.init(
            id: identity,
            owningScope: model?.activeScope.map(ObjectIdentifier.init),
            depth: depth,
            title: title,
            source: source,
            capture: capture,
            roots: roots,
        ))
    }
}

extension EnvironmentValues {
    @Entry fileprivate var portholeContextDepth: Int = 0
}
