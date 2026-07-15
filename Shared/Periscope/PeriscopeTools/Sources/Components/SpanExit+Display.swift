import PeriscopeCore
import SwiftUI

extension SpanExit.Mode {
    /// Capitalized name shown in chips and the exit filter.
    var displayName: String {
        rawValue.capitalized
    }

    /// Chip tint: calm for expected outcomes, hot for the ones worth
    /// chasing.
    var tint: Color {
        switch self {
            case .success: .green
            case .cancelled: .gray
            case .superseded: .yellow
            case .expired: .orange
            case .failure: .red
            case .orphaned: .purple
        }
    }
}

/// The exit-mode chip shown beside span-ended rows and in event detail.
struct SpanExitBadge: View {
    let mode: SpanExit.Mode

    var body: some View {
        Text(mode.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(mode.tint.opacity(0.18), in: .capsule)
            .foregroundStyle(mode.tint)
    }
}
