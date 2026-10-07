import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// A compatibility withdrawal contains no cached locations or counts.
public struct WidgetUnavailableView: View {
    public init() {}
    public var body: some View {
        Label(String(localized: .compatibilityWidgetUnavailable), systemSymbol: .arrowDownApp)
            .font(.caption)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
    extension WidgetUnavailableView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Unavailable", configurations: .componentDefaults) {
                Self()
                    .frame(height: 158)
                    // Match the medium widget host and its container background.
                    .background(.background)
            }
        }
    }

    extension WidgetUnavailableView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            Self.self,
            title: "Widget Unavailable",
            navigationContainer: .none,
        )
    }

    #Preview { WidgetUnavailableView.snapshotPreviews }
#endif
