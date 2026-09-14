import PortholeRemote

#if canImport(UIKit)
    struct PortholeRemoteSnapshotConnector: PortholeRemoteConnecting {
        func discoveredApplications()
            -> AsyncThrowingStream<[PortholeDiscoveredApplication], Error>
        {
            AsyncThrowingStream { $0.yield([]); $0.finish() }
        }

        func pairedServers() async throws -> [PortholePairedServer] {
            []
        }

        func enroll(
            invitation _: PortholeEnrollmentInvitation,
            clientName _: String,
        ) async throws -> PortholePairedServer {
            throw PortholeRemoteError.invalidEnrollment
        }

        func connect(server _: PortholePairedServer) async throws -> PortholeRemoteClient {
            throw PortholeRemoteError.disconnected
        }
    }
#endif
