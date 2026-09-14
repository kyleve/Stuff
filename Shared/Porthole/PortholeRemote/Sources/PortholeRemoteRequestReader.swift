import Foundation

/// A receiver has one reader and must unblock a pending read when cancelled.
protocol PortholeRemoteRequestReceiving: Sendable {
    func receiveRequest() async throws -> Data
    func cancel()
}

/// One receive task detects disconnect independently of a suspended native dispatch.
struct PortholeRemoteRequestReader {
    let requests: AsyncThrowingStream<Data, any Error>
    private let source: any PortholeRemoteRequestReceiving
    private let task: Task<Void, Never>

    init(
        source: any PortholeRemoteRequestReceiving,
        onEnd: @escaping @Sendable () async -> Void,
    ) {
        self.source = source
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(
            bufferingPolicy: .bufferingOldest(1),
        )
        requests = stream
        task = Task {
            let failure: any Error
            do {
                while true {
                    try Task.checkCancellation()
                    let frame = try await source.receiveRequest()
                    guard !frame.isEmpty else { throw PortholeRemoteError.invalidMessage }
                    guard frame.count <= PortholeRemoteFraming.maximumBytes
                    else { throw PortholeRemoteError.frameTooLarge }
                    switch continuation.yield(frame) {
                        case .enqueued: break
                        case .dropped: throw PortholeRemoteError.connectionBusy
                        case .terminated: throw CancellationError()
                        @unknown default: throw PortholeRemoteError.invalidMessage
                    }
                }
            } catch { failure = error }
            source.cancel()
            // This is the only terminal path. Repeated cancellation cannot schedule more cleanup.
            // Cleanup must survive cancellation of either the dispatch task or this receive task.
            await Task { await onEnd() }.value
            continuation.finish(throwing: failure)
        }
    }

    func cancel() {
        task.cancel()
        source.cancel()
    }

    func waitUntilEnded() async {
        await task.value
    }
}
