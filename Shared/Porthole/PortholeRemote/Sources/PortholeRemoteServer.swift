import Foundation
import Network
import os

/// The operational listener always requires mTLS. A separate temporary listener accepts enrollment
/// only.
public actor PortholeRemoteServer {
    public enum State: Sendable, Equatable {
        case stopped
        case starting
        case listening
        case failed(String)
    }

    private struct Session {
        let channel: PortholeConnection
        let task: Task<Void, Never>
        let enrollment: Bool
        let requests: PortholeRemoteSession
    }

    private let identity: PortholeTLSIdentity
    private let trust: PortholePeerTrust
    private let dispatcher: PortholeRemoteDispatcher
    private let serviceName: String
    private let enrollment: PortholeEnrollment
    private let log = Logger(subsystem: "com.stuff.porthole", category: "Remote")
    private var listener: NWListener?
    private var pairingListener: NWListener?
    private var pairingExpiry: Task<Void, Never>?
    private var sessions: [UUID: Session] = [:]
    public private(set) var state: State = .stopped

    public init(
        identity: PortholeTLSIdentity,
        trust: PortholePeerTrust,
        dispatcher: PortholeRemoteDispatcher,
        serviceName: String,
    ) {
        self.identity = identity
        self.trust = trust
        self.dispatcher = dispatcher
        self.serviceName = serviceName
        enrollment = PortholeEnrollment(trust: trust)
    }

    public func start() async throws {
        guard listener == nil else { return }
        try identity.validate(at: Date())
        let listener = try NWListener(using: PortholeTLS.server(
            identity: identity,
            trust: trust,
            enrollment: false,
        ))
        self.listener = listener
        state = .starting
        do {
            try await start(listener, enrollment: false)
            guard self.listener === listener else { throw PortholeRemoteError.disabled }
            state = .listening
        } catch {
            listener.cancel()
            if self
                .listener ===
                listener { self.listener = nil; state = .failed(error.localizedDescription) }
            throw error
        }
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        state = .stopped
        cancelEnrollment()
        let active = Array(sessions.values)
        sessions.removeAll()
        for session in active {
            session.task.cancel(); session.channel.cancel()
        }
        for session in active {
            await session.requests.close()
        }
    }

    public func beginEnrollment() async throws -> PortholeEnrollmentInvitation {
        guard state == .listening else { throw PortholeRemoteError.disabled }
        cancelEnrollment()
        let invitation = try enrollment.begin(
            serviceName: serviceName,
            serverCertificatePin: identity.fingerprint,
            at: Date(),
        )
        let pairing = try NWListener(using: PortholeTLS.server(
            identity: identity,
            trust: trust,
            enrollment: true,
        ))
        pairingListener = pairing
        do {
            try await start(pairing, enrollment: true)
            guard pairingListener === pairing,
                  state == .listening else { throw PortholeRemoteError.disabled }
            pairingExpiry = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(120)); await self?
                        .expireEnrollment(listener: pairing)
                } catch is CancellationError { /* Closing enrollment cancels this deadline. */ }
                catch { await self?.record(error: error) }
            }
            return invitation
        } catch {
            if pairingListener === pairing { cancelEnrollment() }
            throw error
        }
    }

    public func cancelEnrollment() {
        endEnrollment(keepingSessionID: nil)
    }

    private func expireEnrollment(listener: NWListener) {
        if pairingListener === listener { cancelEnrollment() }
    }

    private func endEnrollment(keepingSessionID: UUID?) {
        pairingExpiry?.cancel()
        pairingExpiry = nil
        pairingListener?.cancel()
        pairingListener = nil
        enrollment.cancel()
        for (sessionID, session) in sessions
            where session.enrollment && sessionID != keepingSessionID
        {
            session.task.cancel(); session.channel.cancel()
        }
    }

    public func peers() -> [PortholeTrustedPeer] {
        trust.peers()
    }

    public func revoke(peerID: UUID) throws {
        try trust.revoke(peerID: peerID)
    }

    private func start(_ listener: NWListener, enrollment: Bool) async throws {
        listener.service = NWListener.Service(
            name: serviceName,
            type: enrollment ? "_porthole-pair._tcp" : "_porthole._tcp",
        )
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            guard let listener else { connection.cancel(); return }
            Task { await self?.accept(connection, listener: listener, enrollment: enrollment) }
        }
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.waitForListener(listener, enrollment: enrollment) }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    listener.cancel()
                    throw PortholeRemoteError.timedOut
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } onCancel: { listener.cancel() }
    }

    private func waitForListener(_ listener: NWListener, enrollment: Bool) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            Void,
            any Error
        >) in
            let pending = OSAllocatedUnfairLock(initialState: Optional(continuation))
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                let result: Result<Void, any Error>?
                switch state {
                    case .ready: result = .success(())
                    case let .failed(error):
                        result = .failure(error)
                        if let listener { Task { await self?.listenerFailed(
                            error: error,
                            listener: listener,
                            enrollment: enrollment,
                        ) } }
                    case .cancelled: result = .failure(PortholeRemoteError.disabled)
                    case let .waiting(error): result = .failure(error)
                    case .setup: result = nil
                    @unknown default: result = .failure(PortholeRemoteError.disconnected)
                }
                if let result { pending.withLock { value in
                    value?.resume(with: result); value = nil
                } }
            }
            listener.start(queue: PortholeTLS.queue)
            // Cancellation can precede callback installation during an actor suspension.
            listener.stateUpdateHandler?(listener.state)
        }
    }

    private func accept(_ connection: NWConnection, listener: NWListener, enrollment: Bool) {
        guard state == .listening, sessions.count < 8,
              enrollment ? pairingListener === listener : self.listener === listener
        else { connection.cancel(); return }
        let sessionID = UUID()
        let channel = PortholeConnection(connection)
        let requests = dispatcher.makeSession()
        let task = Task { [weak self] in
            guard let self else { return }
            await serve(channel, sessionID: sessionID, enrollment: enrollment, requests: requests)
        }
        sessions[sessionID] = Session(
            channel: channel,
            task: task,
            enrollment: enrollment,
            requests: requests,
        )
    }

    private func serve(
        _ channel: PortholeConnection,
        sessionID: UUID,
        enrollment isEnrollment: Bool,
        requests: PortholeRemoteSession,
    ) async {
        var reader: PortholeRemoteRequestReader?
        defer { reader?.cancel() }
        defer { channel.cancel(); trust.releaseSession(id: sessionID); sessions[sessionID] = nil }
        do {
            try await channel.start()
            if isEnrollment {
                let request = try await JSONDecoder().decode(
                    PortholeEnrollmentRequest.self,
                    from: channel.receive(),
                )
                let peer = try enrollment.accept(request, at: Date())
                endEnrollment(keepingSessionID: sessionID)
                try await channel.send(JSONEncoder().encode(peer))
                return
            }
            let certificate = try PortholeTLS.peerCertificate(connection: channel.network)
            guard let peer = try trust.peer(for: certificate, at: Date())
            else { throw PortholeRemoteError.untrustedPeer }
            guard let session = sessions[sessionID] else { throw PortholeRemoteError.disconnected }
            try trust.retainSession(
                id: sessionID,
                peerID: peer.id,
                close: {
                    session.task.cancel(); channel.cancel()
                    // A native call can outlive cancellation. End its observation owner now.
                    Task { await session.requests.close() }
                },
            )
            let incoming = PortholeRemoteRequestReader(source: channel) {
                // EOF can arrive while Swift code ignores cancellation. Close ownership
                // independently.
                session.task.cancel()
                await requests.close()
            }
            reader = incoming
            for try await bytes in incoming.requests {
                try Task.checkCancellation()
                let request = try JSONDecoder().decode(
                    PortholeRemoteRequest.self,
                    from: bytes,
                )
                let response = await requests.respond(to: request)
                try Task.checkCancellation()
                try await channel.send(JSONEncoder().encode(response))
            }
        } catch is CancellationError { /* Cancellation closes the session in defer. */ }
        catch { record(error: error) }
        if let reader {
            reader.cancel()
            await reader.waitUntilEnded()
        } else {
            // Session cancellation must not cancel the cleanup invocations themselves.
            await Task { await requests.close() }.value
        }
    }

    private func listenerFailed(error: any Error, listener: NWListener, enrollment: Bool) async {
        guard enrollment ? pairingListener === listener : self.listener === listener else { return }
        record(error: error)
        if enrollment { cancelEnrollment() }
        else { await stop(); state = .failed(error.localizedDescription) }
    }

    private func record(error: any Error) {
        log.error("Remote session ended: \(error.localizedDescription, privacy: .public)")
    }
}
