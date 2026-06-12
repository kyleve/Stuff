import SwiftUI

/// The default placeholder shown while a silent launch step runs and the host
/// passes no custom splash. Intentionally minimal — a centered spinner on the
/// system background.
public struct LaunchSplash: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }
}

#if DEBUG
    #Preview {
        LaunchSplash()
    }
#endif
