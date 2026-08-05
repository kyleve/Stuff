import Foundation

/// Frozen composite state of every protocol machine in the prototype stack.
struct ServicesSnapshot: Equatable {
    var tracking: TrackingMachine.State
    var postWrite: PostWriteMachine.State
    var ingestor: IngestorMachine.State
    var launch: LaunchMachine.State
    var reset: ResetMachine.State

    init(
        tracking: TrackingMachine.State = .initial,
        postWrite: PostWriteMachine.State = .initial,
        ingestor: IngestorMachine.State = .initial,
        launch: LaunchMachine.State = .initial,
        reset: ResetMachine.State = .initial,
    ) {
        self.tracking = tracking
        self.postWrite = postWrite
        self.ingestor = ingestor
        self.launch = launch
        self.reset = reset
    }

    static let initial = ServicesSnapshot()
}
