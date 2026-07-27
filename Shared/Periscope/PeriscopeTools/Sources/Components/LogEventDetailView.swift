import Foundation
import PeriscopeCore
import SwiftUI

/// Everything about one stored event: metadata, message, scope path, tags,
/// the structured payload as pretty-printed JSON, and attachments (bytes
/// loaded on demand).
struct LogEventDetailView: View {
    let event: StoredLogEvent
    let scopePath: String
    let store: PeriscopeStore

    @Environment(\.stylesheet) private var stylesheet
    @State private var attachments: Result<[LogAttachment], Error>?

    var body: some View {
        List {
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
                    LabeledContent("Exit") {
                        HStack(spacing: 6) {
                            SpanExitBadge(mode: exitMode)
                            if let reason = event.exitReason {
                                Text(reason)
                            }
                        }
                    }
                }
                if let callSite = event.callSite {
                    LabeledContent("Emitted From", value: callSite.description)
                }
                if let externalID = event.externalID {
                    LabeledContent("Object", value: externalID)
                }
                LabeledContent("Session", value: event.sessionID.uuidString)
            }

            Section("Message") {
                Text(event.message)
                    .font(stylesheet.typography.message)
                    .textSelection(.enabled)
            }

            if !event.tags.isEmpty {
                Section("Tags") {
                    ForEach(event.tags, id: \.key) { tag in
                        LabeledContent(tag.key.rawValue, value: tag.value.stringValue)
                    }
                }
            }

            if let payload = event.prettyPayload {
                Section("Payload") {
                    Text(payload)
                        .font(stylesheet.typography.payload)
                        .textSelection(.enabled)
                }
            }

            if !event.attachments.isEmpty {
                Section("Attachments") {
                    attachmentsContent
                }
            }
        }
        .navigationTitle(event.eventName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    LogTraceView(store: store, origin: event)
                } label: {
                    Label(
                        "Trace",
                        systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                    )
                }
            }
        }
        .task(id: Inputs(store: ObjectIdentifier(store), event: event.id)) {
            attachments = nil
            do {
                attachments = try await .success(store.attachments(forEvent: event.id))
            } catch {
                attachments = .failure(error)
            }
        }
    }

    /// The identity of this view's inputs — re-keying the task reloads the
    /// attachments when either changes in place.
    private struct Inputs: Equatable {
        let store: ObjectIdentifier
        let event: UUID
    }

    @ViewBuilder
    private var attachmentsContent: some View {
        switch attachments {
            case nil:
                ProgressView()
            case let .failure(error):
                Label(String(describing: error), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case let .success(loaded):
                ForEach(Array(loaded.enumerated()), id: \.offset) { _, attachment in
                    LabeledContent(attachment.name) {
                        Text("\(attachment.contentType.mimeType) · \(attachment.data.count) bytes")
                    }
                }
        }
    }
}

extension StoredLogEvent {
    /// The exit's freeform reason, from the payload (the mode is columnar,
    /// the reason is not); `nil` when there is none or the payload no
    /// longer decodes.
    var exitReason: String? {
        (try? decode(SpanEnded.self))?.exit.reason
    }

    /// The stored payload, pretty-printed; `nil` when the event carried no
    /// structured fields or the payload isn't JSON.
    var prettyPayload: String? {
        guard !payload.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: payload),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys],
              )
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
