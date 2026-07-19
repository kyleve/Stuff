import PeriscopeCore
import SwiftUI

/// The one-line event summary shared by the viewer, tracer, and inspector:
/// severity badge, event type, timestamp, message, and scope path.
struct LogEventRow: View {
    let event: StoredLogEvent
    let scopePath: String

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.logRowDensity) private var density

    var body: some View {
        let row = stylesheet.row[density]
        let type = stylesheet.typography
        VStack(alignment: .leading, spacing: row.lineSpacing) {
            HStack(spacing: row.headerSpacing) {
                LogLevelBadge(level: event.level)
                if let exitMode = event.spanExitMode {
                    SpanExitBadge(mode: exitMode)
                }
                Text(event.eventName)
                    .font(type.eventName)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(event.date, format: .dateTime.hour().minute().second())
                    .font(type.timestamp)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Text(event.message)
                .font(type.message)
                .lineLimit(row.messageLineLimit)
            if !scopePath.isEmpty {
                Text(scopePath)
                    .font(type.scopePath)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, row.verticalPadding)
    }
}

/// The severity badge shared by the viewer, tracer, and inspector.
struct LogLevelBadge: View {
    let level: LogLevel

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let badge = stylesheet.badge
        let tint = stylesheet.palette.tint(forLevel: level)
        Text(level.badgeLabel)
            .font(badge.font)
            .padding(.horizontal, badge.horizontalPadding)
            .padding(.vertical, badge.verticalPadding)
            .background(tint.opacity(badge.backgroundOpacity), in: .capsule)
            .foregroundStyle(tint)
    }
}
