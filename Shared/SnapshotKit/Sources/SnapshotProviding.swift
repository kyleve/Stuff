import SwiftUI

/// A type that declares its snapshot variants in one place, driving both an Xcode
/// preview cutsheet (``snapshotPreviews``) and the image snapshot tests
/// (`assertSnapshots(of:)` in `SnapshotKitTesting`).
///
/// Conform a component and describe its cases with the ``SnapshotCaseBuilder``:
///
/// ```swift
/// extension MyBadge: SnapshotProviding {
///     static var snapshots: [SnapshotCase] {
///         SnapshotCase(name: "States", configurations: .componentRepresentative) {
///             MyBadge(count: 3)
///         }
///     }
/// }
/// ```
public protocol SnapshotProviding {
    @MainActor @SnapshotCaseBuilder static var snapshots: [SnapshotCase] { get }
}

@MainActor
extension SnapshotProviding {
    /// A scrollable cutsheet of every case's non-accessibility variants, for an
    /// Xcode `#Preview`. Accessibility captures are excluded because their
    /// annotation renderer belongs to the test-only `SnapshotKitTesting` product.
    public static var snapshotPreviews: some View {
        SnapshotCutsheet(cases: snapshots)
    }
}

/// Renders a provider's ``SnapshotCase``s stacked with headers.
struct SnapshotCutsheet: View {
    let cases: [SnapshotCase]

    var body: some View {
        ScrollView(cases
            .contains { $0.isCutsheet } ? [.horizontal, .vertical] : [.vertical])
        {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(cases) { snapshotCase in
                    SnapshotCutsheetSection(snapshotCase: snapshotCase)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SnapshotCutsheetSection: View {
    let snapshotCase: SnapshotCase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshotCase.name)
                .font(.headline)
            snapshotCase
        }
    }
}
