import Foundation
import PeriscopeCore
import SFSafeSymbols
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
    /// The event's ambient state, resolved on demand — the inner optional is
    /// "the row is gone", distinct from a failed lookup.
    @State private var ambient: Result<AmbientSnapshot?, Error>?

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

            if event.ambientSnapshotID != nil {
                Section("Ambient") {
                    ambientContent
                }
            }

            if let payload = event.payloadPresentation {
                Section("Payload") {
                    switch payload {
                        case let .json(pretty):
                            Text(pretty)
                                .font(stylesheet.typography.payload)
                                .textSelection(.enabled)
                        case let .unreadable(byteCount):
                            Label(
                                "Unreadable payload (\(byteCount) bytes)",
                                systemSymbol: .exclamationmarkTriangle,
                            )
                            .foregroundStyle(.secondary)
                    }
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
                        systemSymbol: .pointBottomleftForwardToPointToprightScurvepath,
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
            await loadAmbient()
        }
    }

    private func loadAmbient() async {
        ambient = nil
        guard let snapshotID = event.ambientSnapshotID else { return }
        do {
            ambient = try await .success(store.ambientSnapshot(for: snapshotID))
        } catch {
            ambient = .failure(error)
        }
    }

    /// The identity of this view's inputs — re-keying the task reloads the
    /// attachments when either changes in place.
    private struct Inputs: Equatable {
        let store: ObjectIdentifier
        let event: UUID
    }

    /// What the system was doing when the event was recorded — one row per
    /// ambient kind, sorted so the section doesn't reshuffle between events.
    @ViewBuilder
    private var ambientContent: some View {
        switch ambient {
            case nil:
                ProgressView()
            case let .failure(error):
                Label(String(describing: error), systemSymbol: .exclamationmarkTriangle)
                    .foregroundStyle(.secondary)
            case .success(nil):
                Text("No longer stored")
                    .foregroundStyle(.secondary)
            case let .success(.some(snapshot)):
                ForEach(
                    snapshot.values.sorted { $0.key.rawValue < $1.key.rawValue },
                    id: \.key,
                ) { kind, value in
                    LabeledContent(kind.rawValue, value: value.ambientDescription)
                }
        }
    }

    @ViewBuilder
    private var attachmentsContent: some View {
        switch attachments {
            case nil:
                ProgressView()
            case let .failure(error):
                Label(String(describing: error), systemSymbol: .exclamationmarkTriangle)
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

    /// The stored payload as the detail view presents it — `nil` only when
    /// the event carried no structured fields.
    enum PayloadPresentation: Equatable {
        /// Pretty-printed JSON, keys sorted.
        case json(String)
        /// Bytes exist but don't parse. Persisted payloads are `JSONEncoder`
        /// output, so this means on-disk corruption — the view must say a
        /// payload existed and didn't survive, not hide the section as if
        /// none was recorded.
        case unreadable(byteCount: Int)
    }

    var payloadPresentation: PayloadPresentation? {
        guard !payload.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: payload),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys],
              )
        else { return .unreadable(byteCount: payload.count) }
        return .json(String(decoding: data, as: UTF8.self))
    }
}
