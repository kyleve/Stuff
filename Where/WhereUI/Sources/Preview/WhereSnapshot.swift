#if DEBUG
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// Builds a ``SnapshotCase`` whose content is seeded with `whereBroadwayRoot()`,
    /// so WhereUI views resolve trait-aware `WhereStylesheet` tokens under snapshot
    /// (and preview cutsheet) capture without each author repeating the root
    /// wrapper. Use this instead of `SnapshotCase(...)` directly when authoring
    /// WhereUI ``SnapshotProviding`` conformances.
    ///
    /// `onReadyToMeasure` awaits content that changes the Form/List height.
    /// `prepareForCapture` awaits fixture readiness before the first capture settle.
    /// `onReadyToSnapshot` acts on settled UI, then settles its effects before capture.
    /// Both capture hooks must preserve measured height.
    @MainActor
    public func whereSnapshot(
        name: String,
        configurations: [SnapshotConfiguration],
        theme: WhereTheme = .standard,
        measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
        onReadyToMeasure: (@MainActor () async -> Void)? = nil,
        settle: SnapshotSettle = .settled,
        prepareForCapture: (@MainActor () async throws -> Void)? = nil,
        onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) -> SnapshotCase {
        SnapshotCase(
            name: name,
            configurations: configurations,
            referenceGroup: theme.snapshotReferenceGroup,
            measurementReadiness: measurementReadiness,
            onReadyToMeasure: onReadyToMeasure,
            settle: settle,
            prepareForCapture: prepareForCapture,
            onReadyToSnapshot: onReadyToSnapshot,
        ) {
            content().whereBroadwayRoot(theme: theme)
        }
    }

    extension WhereTheme {
        var snapshotReferenceGroup: SnapshotReferenceGroup? {
            switch self {
                case .standard: nil
                case .alternate: SnapshotReferenceGroup(rawValue: "flat")!
            }
        }
    }

    /// One production component state in every supported theme, freshly built per panel.
    @MainActor
    func whereThemeSnapshot(
        name: String,
        configurations: [SnapshotConfiguration],
        measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
        onReadyToMeasure: (@MainActor () async -> Void)? = nil,
        settle: SnapshotSettle = .settled,
        prepareForCapture: (@MainActor () async throws -> Void)? = nil,
        onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) -> SnapshotCase {
        .cutsheet(
            name: name,
            configurations: configurations,
            referenceGroup: .themes,
            measurementReadiness: measurementReadiness,
            onReadyToMeasure: onReadyToMeasure,
            settle: settle,
            prepareForCapture: prepareForCapture,
            onReadyToSnapshot: onReadyToSnapshot,
        ) {
            for theme in WhereTheme.allCases {
                SnapshotPanel(id: .init(rawValue: theme.rawValue), label: theme.title) {
                    content().whereBroadwayRoot(theme: theme)
                }
            }
        }
    }

#endif
