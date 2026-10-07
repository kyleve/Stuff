import Foundation
@_spi(Testing) @testable import WhereCore

enum CompatibilityOutputTestSupport {
    struct Gate {
        struct Channel {
            let stream: AsyncStream<Void>
            let continuation: AsyncStream<Void>.Continuation

            init() {
                (stream, continuation) = AsyncStream<Void>
                    .makeStream(bufferingPolicy: .bufferingNewest(1))
            }
        }

        let entered = Channel()
        let release = Channel()

        func suspend() async {
            entered.continuation.yield()
            for await _ in release.stream {
                break
            }
        }

        func waitUntilEntered() async {
            for await _ in entered.stream {
                break
            }
        }

        func resume() {
            release.continuation.yield(); release.continuation.finish()
        }
    }
}
