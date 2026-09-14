import SFSafeSymbols
import SwiftUI
#if canImport(UIKit)
    import SnapshotKit
#endif

/// Agent setup errors leave manual tools available and never discard saved investigations.
struct PortholeAgentConfigurationFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label("Agent setup failed", systemSymbol: .exclamationmarkTriangle)
            } description: {
                Text("Manual tools remain available. Retry to open the saved investigation.")
                Text(message)
            } actions: {
                Button("Retry agent setup", action: retry)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .navigationTitle("Ask")
    }
}

#if canImport(UIKit)
    extension PortholeAgentConfigurationFailureView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(name: "SetupFailure", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    Self(message: "The saved investigation could not be read.", retry: {})
                }.portholeBroadwayRoot()
            }
        }
    }

    #if DEBUG
        #Preview { PortholeAgentConfigurationFailureView.snapshotPreviews }
    #endif
#endif
