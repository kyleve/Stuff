import ThrowCore

/// Observable readiness of Throw's process-owned durable diagnostics store.
public enum ThrowDurableLoggingState: Equatable, Sendable {
    /// No starter was installed, as in previews and unit-test fixtures.
    case unavailable
    /// The on-disk store is opening while OSLog remains active.
    case opening
    /// The store is attached and receives process log records.
    case ready
    /// Opening failed. OSLog remains active for this process.
    case failed
}

extension ThrowSession {
    /// Starts one process-owned durable logging attempt.
    func startDurableLogging() {
        guard durableLoggingState == .unavailable,
              durableLoggingTask == nil,
              let durableLoggingStarter
        else { return }

        durableLoggingState = .opening
        durableLoggingTask = Task(name: "Throw start durable logging") { [weak self] in
            do {
                let loggingSession = try await durableLoggingStarter.start()
                guard let self else { return }
                durableLoggingSession = loggingSession
                durableLoggingState = .ready
                await loggingSession.pruneHistory()
            } catch {
                self?.durableLoggingState = .failed
            }
            self?.durableLoggingTask = nil
        }
    }

    #if DEBUG
        @_spi(Testing) public func waitForDurableLoggingForTesting() async {
            await durableLoggingTask?.value
        }
    #endif
}
