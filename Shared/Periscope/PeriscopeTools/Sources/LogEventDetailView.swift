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
                LabeledContent("Session", value: event.sessionID.uuidString)
            }

            Section("Message") {
                Text(event.message)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if !event.tags.isEmpty {
                Section("Tags") {
                    ForEach(
                        event.tags.sorted { $0.key.rawValue < $1.key.rawValue },
                        id: \.key,
                    ) { key, value in
                        LabeledContent(key.rawValue, value: value)
                    }
                }
            }

            if let payload = prettyPayload {
                Section("Payload") {
                    Text(payload)
                        .font(.caption.monospaced())
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
        .task {
            do {
                attachments = try await .success(store.attachments(forEvent: event.id))
            } catch {
                attachments = .failure(error)
            }
        }
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
                        Text("\(attachment.contentType) · \(attachment.data.count) bytes")
                    }
                }
        }
    }

    /// The stored payload, pretty-printed; `nil` when the event carried no
    /// structured fields or the payload isn't JSON.
    private var prettyPayload: String? {
        guard !event.payload.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: event.payload),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys],
              )
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
