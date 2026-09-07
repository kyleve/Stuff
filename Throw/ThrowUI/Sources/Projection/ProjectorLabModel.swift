#if DEBUG
    import Observation

    @MainActor
    @Observable
    final class ProjectorLabModel {
        private let session: ThrowSession
        private let outputID: ProjectionOutputID

        var aspectRatio: ProjectorLabAspectRatio = .sixteenByNine
        var isConnected = false {
            didSet {
                guard oldValue != isConnected else { return }
                if isConnected {
                    session.projectionOutputConnected(.externalDisplay(outputID))
                } else {
                    session.projectionOutputDisconnected(.externalDisplay(outputID))
                }
            }
        }

        init(session: ThrowSession, outputID: ProjectionOutputID) {
            self.session = session
            self.outputID = outputID
        }

        func disconnect() {
            isConnected = false
        }
    }
#endif
