import LifecycleKit
import SwiftUI

/// The UI shown while a launch step migrates the SwiftData store. Bound to the
/// step's `LifecycleStepUIBridge`: it shows a determinate bar if the step
/// reports `progress`, otherwise an indeterminate spinner (SwiftData migrations
/// give no progress callback today), and surfaces the bridge's `message` if set.
public struct MigrationProgressView: View {
    private let bridge: LifecycleStepUIBridge

    public init(bridge: LifecycleStepUIBridge) {
        self.bridge = bridge
    }

    public var body: some View {
        VStack(spacing: UIConstants.Spacings.xxxLarge) {
            if let progress = bridge.progress {
                ProgressView(value: progress) {
                    Text(Strings.migrationTitle)
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text(Strings.migrationTitle)
                    .font(.headline)
            }

            Text(bridge.message ?? Strings.migrationSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(UIConstants.Spacings.xxxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#if DEBUG
    #Preview("Indeterminate") {
        MigrationProgressView(bridge: LifecycleStepUIBridge(reason: .userForeground))
    }

    #Preview("Determinate") {
        let bridge = LifecycleStepUIBridge(reason: .userForeground)
        bridge.progress = 0.4
        bridge.message = "Migrating manual days…"
        return MigrationProgressView(bridge: bridge)
    }
#endif
