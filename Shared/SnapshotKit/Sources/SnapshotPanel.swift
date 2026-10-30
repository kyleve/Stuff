import SwiftUI

/// One independently hosted subject in a comparison sheet. Builders must create
/// fresh fixture state; shared immutable resources and readiness hooks are safe.
public struct SnapshotPanel: Identifiable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let label: String
    private let contentFactory: @MainActor () -> AnyView
    @_spi(Capture) @MainActor public var content: AnyView {
        contentFactory()
    }

    public init(
        id: ID,
        label: String,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) {
        self.id = id
        self.label = label
        contentFactory = { AnyView(content()) }
    }
}
