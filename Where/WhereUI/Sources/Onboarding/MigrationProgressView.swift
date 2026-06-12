import LifecycleKit
import SwiftUI

/// The UI shown while a launch step migrates the SwiftData store. Bound to the
/// step's `StepHandle`: it shows a determinate bar if the step reports
/// `progress`, otherwise an indeterminate spinner (SwiftData migrations give no
/// progress callback today), and surfaces the handle's `message` if set.
public struct MigrationProgressView: View {
    private let handle: StepHandle

    public init(handle: StepHandle) {
        self.handle = handle
    }

    public var body: some View {
        VStack(spacing: UIConstants.Spacings.xxxLarge) {
            if let progress = handle.progress {
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

            Text(handle.message ?? Strings.migrationSubtitle)
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
        MigrationProgressView(handle: StepHandle(reason: .userForeground))
    }

    #Preview("Determinate") {
        let handle = StepHandle(reason: .userForeground)
        handle.progress = 0.4
        handle.message = "Migrating manual days…"
        return MigrationProgressView(handle: handle)
    }
#endif
