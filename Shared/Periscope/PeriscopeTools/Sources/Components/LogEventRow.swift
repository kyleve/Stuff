import PeriscopeCore
import SwiftUI

/// The one-line event summary shared by the viewer, tracer, and inspector:
/// severity badge, event type, timestamp, message, and scope path.
struct LogEventRow: View {
    let event: StoredLogEvent
    let scopePath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                LogLevelBadge(level: event.level)
                if let exitMode = event.spanExitMode {
                    SpanExitBadge(mode: exitMode)
                }
                Text(event.eventName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(event.date, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Text(event.message)
                .font(.callout)
                .lineLimit(3)
            if !scopePath.isEmpty {
                Text(scopePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The severity badge shared by the viewer, tracer, and inspector.
struct LogLevelBadge: View {
    let level: LogLevel

    var body: some View {
        Text(level.badgeLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(level.tint.opacity(0.18), in: .capsule)
            .foregroundStyle(level.tint)
    }
}
