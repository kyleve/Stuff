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
    @MainActor public var content: AnyView {
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

extension SnapshotCase {
    /// Each configuration becomes one labeled, two-column comparison image.
    @MainActor public static func comparison(
        name: String,
        configurations: [SnapshotConfiguration],
        referenceGroup: SnapshotReferenceGroup = .themes,
        measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
        onReadyToMeasure: (@MainActor () async -> Void)? = nil,
        settle: SnapshotSettle = .settled,
        onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
        panels: [SnapshotPanel],
    ) -> SnapshotCase {
        precondition(
            !panels.isEmpty && Set(panels.map(\.id)).count == panels.count,
            "Comparison panels require distinct identities and at least one subject",
        )
        return SnapshotCase(
            name: name,
            configurations: configurations,
            referenceGroup: referenceGroup,
            comparisonPanels: panels,
            measurementReadiness: measurementReadiness,
            onReadyToMeasure: onReadyToMeasure,
            settle: settle,
            onReadyToSnapshot: onReadyToSnapshot,
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(panels) { panel in
                    VStack(alignment: .leading) {
                        Text(panel.label).font(.caption)
                        panel.content
                    }
                }
            }
        }
    }
}
