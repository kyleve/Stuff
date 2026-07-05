import ForemanCore
import SwiftUI

/// A live tail of one worker's log file, polled once a second while visible
/// (workers append continuously; there's no push signal for file growth).
struct WorkerLogView: View {
    /// What the last poll produced. One value, so "no file", content, and a
    /// read failure can't coexist.
    private enum Tail {
        case noFileYet
        case content(String)
        case failed(String)
    }

    let url: URL

    @State private var tail: Tail = .noFileYet

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
        .task(id: url) {
            while !Task.isCancelled {
                refresh()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return // Cancelled: the view went away.
                }
            }
        }
    }

    private func refresh() {
        do {
            if let text = try LogTailReader.tail(of: url, maxBytes: 64 * 1024) {
                tail = .content(text)
            } else {
                tail = .noFileYet
            }
        } catch {
            tail = .failed("Couldn't read the log: \(error.localizedDescription)")
        }
    }
}
