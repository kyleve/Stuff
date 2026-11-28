import PeriscopeCore
import SFSafeSymbols
import SwiftUI

struct LogEventMetadataSection: View {
    let event: StoredLogEvent
    let scopePath: String

    var body: some View {
        Section("Event") {
            LabeledContent("Level") {
                LogLevelBadge(level: event.level)
            }
            LabeledContent("Type", value: "\(event.eventName) v\(event.eventVersion)")
            LabeledContent(
                "Date",
                value: event.date.formatted(date: .abbreviated, time: .standard),
            )
            if !scopePath.isEmpty {
                LabeledContent("Scope", value: scopePath)
            }
            if let span = event.spanID {
                LabeledContent("Span", value: span.description)
            }
            if let exitMode = event.spanExitMode {
                LogEventExitRow(mode: exitMode, reason: event.exitReason)
            }
            if let callSite = event.callSite {
                LabeledContent("Emitted From", value: callSite.description)
            }
            if let externalID = event.externalID {
                LabeledContent("Object", value: externalID)
            }
            LabeledContent("Session", value: event.sessionID.uuidString)
        }
    }
}

private struct LogEventExitRow: View {
    let mode: SpanExit.Mode
    let reason: String?

    var body: some View {
        LabeledContent("Exit") {
            HStack(spacing: 6) {
                SpanExitBadge(mode: mode)
                if let reason {
                    Text(reason)
                }
            }
        }
    }
}

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            LogEventDetailView(
                event: fixture.event,
                scopePath: fixture.scope.name,
                store: fixture.store,
            )
        }
    }
#endif
