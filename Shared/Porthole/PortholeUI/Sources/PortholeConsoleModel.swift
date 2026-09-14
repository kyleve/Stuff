import Foundation
import Observation
import PortholeJavaScript
import PortholeRuntime

/// A console run freezes its scope and uses the same approval path as native forms.
@MainActor @Observable
final class PortholeConsoleModel {
    struct Entry: Identifiable {
        let id: UUID
        let label: String
        let value: PortholeValue?
    }

    enum State {
        case idle, running, finished(PortholeValue), failed(String), cancelled
    }

    var source = """
    await porthole.call("porthole.discover", {
      arguments: { query: "", offset: 0, limit: 20 }
    })
    """
    private(set) var state: State = .idle
    private(set) var entries: [Entry] = []
    @ObservationIgnored private var session: PortholeJavaScriptSession?
    @ObservationIgnored private var operation: Task<Void, Never>?
    private var runID: UUID?

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    func run(using controller: PortholePresentationController) {
        guard !isRunning, let scope = controller.origin?.scope else { return }
        let runID = UUID()
        self.runID = runID
        entries = []
        let session = PortholeJavaScriptSession(limits: .interactive, nativeCall: { name, payload in
            guard let arguments = payload["arguments"] else {
                throw PortholeError
                    .invalidArguments(
                        "Use porthole.call(id, {arguments: {...}, receiver: optionalReference}).",
                    )
            }
            let receiver: PortholeObjectReference? = if let value = payload["receiver"],
                                                        value != .null
            {
                try value.decode(PortholeObjectReference.self)
            } else { nil }
            return try await controller.execute(PortholeInvocation(
                id: UUID(),
                scope: scope,
                capabilityID: .init(rawValue: name),
                receiver: receiver,
                arguments: arguments,
            ))
        }, events: { [weak self] event in
            Task { @MainActor in
                guard self?.runID == runID else { return }
                self?.record(event)
            }
        })
        self.session = session
        state = .running
        let source = source
        operation = Task { [weak self] in
            do {
                let value = try await session.execute(source: source)
                self?.state = .finished(value)
            } catch is CancellationError {
                self?.state = .cancelled
            } catch {
                PortholeUILog.failures
                    .error(
                        "Console evaluation failed: \(String(describing: error), privacy: .private)",
                    )
                self?.state = .failed(String(describing: error))
            }
            self?.session = nil
            self?.operation = nil
        }
    }

    func cancel() {
        operation?.cancel()
        session?.cancel()
    }

    private func record(_ event: PortholeJavaScriptEvent) {
        let entry = switch event {
            case .started: Entry(id: UUID(), label: "Evaluation started", value: nil)
            case let .nativeCall(_, name, arguments): Entry(
                    id: UUID(),
                    label: name,
                    value: arguments,
                )
            case let .nativeResult(_, value): Entry(
                    id: UUID(),
                    label: "Native result",
                    value: value,
                )
            case let .nativeFailure(_, message): Entry(
                    id: UUID(),
                    label: "Native failure: \(message)",
                    value: nil,
                )
            case let .finished(_, value): Entry(
                    id: UUID(),
                    label: "Evaluation result",
                    value: value,
                )
            case let .failed(_, error): Entry(
                    id: UUID(),
                    label: "Evaluation failed: \(error)",
                    value: nil,
                )
        }
        entries.append(entry)
    }
}
