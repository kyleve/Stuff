import ForemanCore
import SwiftUI

/// A live tail of one worker's log file, polled once a second while visible
/// (workers append continuously; there's no push signal for file growth).
struct WorkerLogView: View {
    /// What the last poll produced. One value, so "no file", content, and a
    /// read failure can't coexist. Equatable so unchanged polls can be
    /// dropped instead of re-rendering (see `refresh`).
    private enum Tail: Equatable {
        case noFileYet
        case content(String)
        case failed(String)
    }

    /// Identity for the polling task: restart it when the file changes, and
    /// cancel/relaunch it as the window hides/shows.
    private struct PollKey: Equatable {
        let url: URL
        let isWindowVisible: Bool
    }

    let url: URL

    @State private var tail: Tail = .noFileYet
    @State private var isWindowVisible = true

    var body: some View {
        Group {
            switch tail {
                case .noFileYet:
                    Text("No log yet — this worker hasn't started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case let .content(text):
                    ScrollView {
                        Text(text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: 220)
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
            }
        }
        .background(WindowVisibilityReader(isVisible: $isWindowVisible))
        // Hiding the window does NOT tear the hierarchy down or cancel .task
        // (verified empirically — see WindowVisibilityReader), so gate the
        // polling on window visibility too or a hidden Foreman would keep
        // reading the tail once a second forever.
        .task(id: PollKey(url: url, isWindowVisible: isWindowVisible)) {
            guard isWindowVisible else { return }
            while !Task.isCancelled {
                refresh()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return // Cancelled: the view went away or the window hid.
                }
            }
        }
    }

    private func refresh() {
        let latest: Tail
        do {
            if let text = try LogTailReader.tail(of: url, maxBytes: 64 * 1024) {
                latest = .content(text)
            } else {
                latest = .noFileYet
            }
        } catch {
            latest = .failed("Couldn't read the log: \(error.localizedDescription)")
        }
        // Only write when the tail actually changed: an idle worker polls the
        // same content once a second, and each redundant @State write re-runs
        // body, wiping the user's text selection and churning the scroll view.
        if latest != tail {
            tail = latest
        }
    }
}
