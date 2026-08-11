import SnapshotKit
import SwiftUI

/// The native indeterminate activity indicator with a deterministic capture
/// state. Live UI remains a system `ProgressView`; snapshot capture substitutes
/// its final static silhouette so an endless spinner cannot prevent settling.
struct SystemActivityIndicator: View {
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    var tint: Color

    var body: some View {
        if isCapturingSnapshot {
            Image(systemName: "circle.dotted")
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .tint(tint)
        }
    }
}
