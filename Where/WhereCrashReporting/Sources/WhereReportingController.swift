/// A process-wide diagnostic-reporting controller started during application launch.
@MainActor
public protocol WhereReportingController {
    func start()
}
