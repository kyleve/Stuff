import Flagger
import SwiftUI

struct FlaggerEditorRow: View {
    let flag: FlagSnapshot
    let model: FlaggerModel

    var body: some View {
        NavigationLink {
            FlaggerValueEditor(flag: flag, model: model)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(flag.name)
                    Spacer()
                    if flag.failure != nil {
                        Label("Invalid", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                    } else if flag.hasPendingChange {
                        Text("Next lifetime")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if flag.isDefault == false {
                        Text("Override")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(flag.id.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack {
                    Text(flag.behavior.label)
                    if flag.isFrozen { Text("Frozen") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

extension FeatureFlagBehaviorKind {
    var label: String {
        switch self {
            case .readOnceOnLaunch: "Launch"
            case .readOnceOnFirstAccess: "First read"
            case .liveUpdating: "Live"
        }
    }
}
