import CQuickJS
import Foundation
import PortholeCore
import Synchronization

/// Runs bounded JavaScript on a private serial queue. Each evaluation owns its VM.
/// Native calls use the same injected dispatcher as the explorer and remote clients.
public final class PortholeJavaScriptSession: Sendable {
    public typealias NativeCall = @Sendable (String, PortholeValue) async throws -> PortholeValue
    public typealias EventHandler = @Sendable (PortholeJavaScriptEvent) -> Void

    private let limits: PortholeJavaScriptLimits
    private let nativeCall: NativeCall
    private let events: EventHandler
    private let queue = DispatchQueue(label: "com.stuff.porthole.javascript", qos: .userInitiated)
    private let active = Mutex<JavaScriptRun?>(nil)

    public init(
        limits: PortholeJavaScriptLimits,
        nativeCall: @escaping NativeCall,
        events: @escaping EventHandler,
    ) {
        self.limits = limits
        self.nativeCall = nativeCall
        self.events = events
    }

    /// Supports top-level await and returns the final expression as a JSON value.
    /// Statements without a value return null. Bindings belong to this evaluation.
    public func execute(source: String) async throws -> PortholeValue {
        guard limits.isValid else { throw PortholeJavaScriptError.invalidConfiguration }
        guard source.utf8.count <= limits.sourceBytes, !source.utf8.contains(0) else {
            throw PortholeJavaScriptError.sourceTooLarge
        }
        let run = JavaScriptRun(limits: limits, nativeCall: nativeCall, events: events)
        let accepted = active.withLock { current in
            guard current == nil else { return false }
            current = run
            return true
        }
        guard accepted else { throw PortholeJavaScriptError.busy }
        defer { active.withLock { $0 = nil } }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    continuation.resume(with: Result { try run.evaluate(source: source) })
                }
            }
        } onCancel: {
            run.cancel()
        }
    }

    /// Interrupts JavaScript and requests cancellation of native tasks.
    /// A native operation can finish a mutation before it observes cancellation.
    public func cancel() {
        active.withLock { $0 }?.cancel()
    }
}

/// The engine calls this value synchronously on its owner queue. Other threads
/// communicate only through its mutex and semaphore, never through QuickJS values.
private final class JavaScriptRun: Sendable {
    private struct Completion {
        enum Outcome {
            case value(PortholeValue, json: String)
            case failure(message: String, json: String)
        }

        let callID: UInt64
        let outcome: Outcome
    }

    private struct State {
        var cancelled = false
        var finished = false
        var tasks: [UInt64: Task<Void, Never>] = [:]
        var completions: [Completion] = []
    }

    private let runID = UUID()
    private let limits: PortholeJavaScriptLimits
    private let nativeCall: PortholeJavaScriptSession.NativeCall
    private let events: PortholeJavaScriptSession.EventHandler
    private let deadline: ContinuousClock.Instant
    private let state = Mutex(State())
    private let wake = DispatchSemaphore(value: 0)

    init(
        limits: PortholeJavaScriptLimits,
        nativeCall: @escaping PortholeJavaScriptSession.NativeCall,
        events: @escaping PortholeJavaScriptSession.EventHandler,
    ) {
        self.limits = limits
        self.nativeCall = nativeCall
        self.events = events
        deadline = .now.advanced(by: limits.duration)
    }

    private var interruption: PortholeJavaScriptError? {
        if state.withLock({ $0.cancelled }) { return .cancelled }
        if ContinuousClock.now >= deadline { return .timedOut }
        return nil
    }

    func cancel() {
        let tasks = state.withLock { state in
            state.cancelled = true
            return Array(state.tasks.values)
        }
        for task in tasks {
            task.cancel()
        }
        wake.signal()
    }

    private func finish() {
        let tasks = state.withLock { state in
            state.finished = true
            let tasks = Array(state.tasks.values)
            state.tasks.removeAll()
            state.completions.removeAll()
            return tasks
        }
        for task in tasks {
            task.cancel()
        }
    }

    func evaluate(source: String) throws -> PortholeValue {
        events(.started(runID: runID))
        defer { finish() }
        do {
            let value = try evaluateEngine(source: source)
            events(.finished(runID: runID, value: value))
            return value
        } catch {
            let failure = interruption ?? (error as? PortholeJavaScriptError)
                ?? .executionFailed(String(describing: error))
            events(.failed(runID: runID, error: failure))
            throw failure
        }
    }

    private func evaluateEngine(source: String) throws -> PortholeValue {
        if let interruption { throw interruption }
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        guard let runtime = porthole_js_create(
            limits.heapBytes,
            limits.stackBytes,
            limits.valueBytes,
            limits.nativeCalls,
            { opaque, callID, name, arguments in
                guard let opaque, let name, let arguments else { return }
                let run = Unmanaged<JavaScriptRun>.fromOpaque(opaque).takeUnretainedValue()
                run.invoke(
                    callID: callID,
                    name: String(cString: name),
                    json: String(cString: arguments),
                )
            },
            { opaque in
                guard let opaque else { return true }
                return Unmanaged<JavaScriptRun>.fromOpaque(opaque).takeUnretainedValue()
                    .interruption != nil
            },
            opaque,
        ) else { throw PortholeJavaScriptError.engineUnavailable }
        defer { porthole_js_destroy(runtime) }
        guard porthole_js_begin(runtime, source) == 0 else {
            throw engineError(runtime)
        }
        while true {
            if let interruption { throw interruption }
            let completions = state.withLock { state in
                let completions = state.completions
                state.completions.removeAll()
                return completions
            }
            for completion in completions {
                let eventID = PortholeJavaScriptEvent.CallID(
                    runID: runID,
                    sequence: completion.callID,
                )
                let status: Int32
                switch completion.outcome {
                    case let .value(value, json):
                        events(.nativeResult(callID: eventID, value: value))
                        status = porthole_js_complete(runtime, completion.callID, json, false)
                    case let .failure(message, json):
                        events(.nativeFailure(callID: eventID, message: message))
                        status = porthole_js_complete(runtime, completion.callID, json, true)
                }
                guard status == 0 else {
                    throw engineError(runtime)
                }
            }
            switch porthole_js_pump(runtime) {
                case 1:
                    if let interruption { throw interruption }
                    guard let json = porthole_js_result(runtime) else {
                        throw PortholeJavaScriptError
                            .executionFailed("The engine returned no result")
                    }
                    return try PortholeValue.parse(Data(String(cString: json).utf8))
                case -1:
                    throw engineError(runtime)
                default:
                    // Await native completions without occupying Swift's cooperative pool.
                    // The deadline still applies to a promise that never settles.
                    _ = wake.wait(timeout: .now() + .milliseconds(10))
            }
        }
    }

    private func engineError(_ runtime: OpaquePointer) -> PortholeJavaScriptError {
        if let interruption { return interruption }
        let message = porthole_js_error(runtime).map(String.init(cString:))
            ?? "JavaScript execution failed"
        return .executionFailed(message)
    }

    private func invoke(callID: UInt64, name: String, json: String) {
        guard interruption == nil else { return }
        let eventID = PortholeJavaScriptEvent.CallID(runID: runID, sequence: callID)
        do {
            let arguments = try PortholeValue.parse(Data(json.utf8))
            events(.nativeCall(callID: eventID, name: name, arguments: arguments))
            state.withLock { state in
                guard !state.finished, !state.cancelled else { return }
                // Install while locked so an immediate completion cannot precede registration.
                state.tasks[callID] = Task { [self] in
                    do {
                        try Task.checkCancellation()
                        let value = try await nativeCall(name, arguments)
                        try Task.checkCancellation()
                        let encoded = try value.data()
                        guard encoded.count <= limits.valueBytes
                        else { throw PortholeJavaScriptError.valueTooLarge }
                        complete(Completion(
                            callID: callID,
                            outcome: .value(value, json: String(decoding: encoded, as: UTF8.self)),
                        ))
                    } catch {
                        completeFailure(callID: callID, error: error)
                    }
                }
            }
        } catch {
            completeFailure(callID: callID, error: error)
        }
    }

    private func completeFailure(callID: UInt64, error: any Error) {
        let message = String(String(describing: error).prefix(limits.valueBytes / 8))
        do {
            let encoded = try PortholeValue.string(message).data()
            complete(Completion(
                callID: callID,
                outcome: .failure(message: message, json: String(decoding: encoded, as: UTF8.self)),
            ))
        } catch {
            // Keep the encoding failure observable even if the native error cannot be encoded.
            complete(Completion(callID: callID, outcome: .failure(
                message: "Native error encoding failed: \(error)",
                json: "\"Native error encoding failed\"",
            )))
        }
    }

    private func complete(_ completion: Completion) {
        state.withLock { state in
            state.tasks.removeValue(forKey: completion.callID)
            guard !state.finished, !state.cancelled else { return }
            state.completions.append(completion)
        }
        wake.signal()
    }
}
