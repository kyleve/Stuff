import LifecycleKitUI
import SwiftUI

/// Blocking recovery shown when CloudKit retires this installation identity.
struct RemovedDeviceView: View {
    @Environment(\.lifecycle) private var lifecycle
    @Environment(\.stylesheet) private var stylesheet

    let model: WhereModel
    let session: WhereSession

    var body: some View {
        VStack(spacing: stylesheet.spacing.xxLarge) {
            Image(systemName: "iphone.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: stylesheet.spacing.medium) {
                Text(String(localized: .deviceRemovedTitle))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: .deviceRemovedDescription))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(String(localized: .deviceRemovedRejoin)) {
                Task {
                    await lifecycle.teardown(
                        WhereLaunch.rejoinPlan(for: model),
                        input: session,
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(stylesheet.spacing.xxxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
    #Preview {
        RemovedDeviceView(
            model: PreviewSupport.loadedModel(),
            session: PreviewSupport.loadedSession(),
        )
        .whereBroadwayRoot()
    }
#endif
