import Darwin
import ForemanCore
import Foundation

/// A tiny newline-delimited-JSON server over a Unix domain socket.
///
/// Each connection carries exactly one ``ControlRequest`` line and gets one
/// ``ControlResponse`` line back, then closes. The only client is the
/// `foreman-mcp` server; access control is the socket file's `0600`
/// permissions (Foreman isn't sandboxed), so there's no port or token to
/// juggle.
///
/// Raw socket syscalls run on a background queue; each decoded request hops to
/// the main actor to reach ``ControlRequestHandler`` (and thus
/// `ForemanServices`), and the reply is written back off the main actor.
@MainActor
final class ControlServer {
    private let socketURL: URL
    private let handler: ControlRequestHandler
    /// Accepts run here, one at a time; each accepted connection is then served
    /// on ``workQueue`` so a slow client can't stall the accept loop.
    private let acceptQueue = DispatchQueue(
        label: "com.stuff.foreman.control.accept",
        qos: .utility,
    )
    /// Per-connection read/handle/write. Concurrent so one hung client doesn't
    /// block the others (paired with a receive timeout below).
    private let workQueue = DispatchQueue(
        label: "com.stuff.foreman.control.work",
        qos: .utility,
        attributes: .concurrent,
    )
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    /// How long a connection may take to deliver its one request line before
    /// the read is abandoned (SO_RCVTIMEO). The only client writes it
    /// immediately, so this just bounds a stalled/half-open peer.
    private static let readTimeout = 15.0

    private static let logger = ForemanLog.channel(.app)

    init(socketURL: URL, handler: ControlRequestHandler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    /// Binds and listens on the socket. A failure is logged and leaves the
    /// server inert — the MCP degrades gracefully when Foreman is unreachable,
    /// so a bind failure must never take the app down.
    func start() {
        guard listenFD < 0 else { return }
        // Writing to a socket the peer already closed would otherwise raise
        // SIGPIPE and kill the process.
        signal(SIGPIPE, SIG_IGN)

        let path = socketURL.path
        guard path.utf8.count < 104 else {
            Self.logger.error("Control socket path too long for sun_path: \(path)")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: socketURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
        } catch {
            Self.logger.error("Couldn't create control socket directory: \(error)")
            return
        }
        // A stale socket file from a previous run blocks bind with EADDRINUSE.
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Self.logger.error("Couldn't create control socket: errno \(errno)")
            return
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            path.withCString { source in
                strncpy(destination, source, sunPathCapacity - 1)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else {
            Self.logger.error("Couldn't bind control socket: errno \(errno)")
            close(fd)
            return
        }
        chmod(path, 0o600)

        guard listen(fd, 8) == 0 else {
            Self.logger.error("Couldn't listen on control socket: errno \(errno)")
            close(fd)
            unlink(path)
            return
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else { return }
            Self.configureClient(clientFD)
            // Hand the connection off so the accept loop stays responsive even
            // if this client is slow to send.
            workQueue.async { [weak self] in self?.serve(clientFD) }
        }
        source.setCancelHandler {
            close(fd)
        }
        acceptSource = source
        source.resume()
        Self.logger.info("Control socket listening at \(path)")
    }

    /// Suppresses SIGPIPE on writes and bounds how long a read may block, so a
    /// peer that connects but never finishes sending can't pin a work thread.
    private nonisolated static func configureClient(_ clientFD: Int32) {
        var noSigpipe: Int32 = 1
        setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigpipe,
            socklen_t(MemoryLayout<Int32>.size),
        )
        var timeout = timeval(
            tv_sec: Int(readTimeout),
            tv_usec: 0,
        )
        setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size),
        )
    }

    /// Stops listening and removes the socket file.
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        unlink(socketURL.path)
    }

    /// Reads one request line off `clientFD` (already on the background
    /// queue), handles it on the main actor, and writes the reply back off the
    /// main actor. A malformed line still gets a `.failure` reply so the
    /// client never hangs waiting.
    private nonisolated func serve(_ clientFD: Int32) {
        guard let line = Self.readLine(clientFD), !line.isEmpty else {
            close(clientFD)
            return
        }

        let request: ControlRequest
        do {
            request = try JSONDecoder().decode(ControlRequest.self, from: line)
        } catch {
            Self.write(
                clientFD,
                Self.encode(.failure(message: "Malformed request: \(error.localizedDescription)")),
            )
            close(clientFD)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                close(clientFD)
                return
            }
            let response = await handler.handle(request)
            let data = Self.encode(response)
            workQueue.async {
                Self.write(clientFD, data)
                close(clientFD)
            }
        }
    }

    private nonisolated static func encode(_ response: ControlResponse) -> Data {
        (try? JSONEncoder().encode(response)) ??
            Data(#"{"ok":false,"error":"encoding failed"}"#.utf8)
    }

    /// Reads bytes up to (and consuming) a newline, returning the bytes before
    /// it; `nil` on error. Requests are tiny, so byte-at-a-time is fine.
    private nonisolated static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            if count == 1 {
                if byte == 0x0A { return data }
                data.append(byte)
                if data.count > 1_048_576 { return nil }
            } else if count == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                return nil
            }
        }
    }

    private nonisolated static func write(_ fd: Int32, _ payload: Data) {
        var data = payload
        data.append(0x0A)
        data.withUnsafeBytes { raw in
            guard var base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, base, remaining)
                if written > 0 {
                    base += written
                    remaining -= written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }
}
