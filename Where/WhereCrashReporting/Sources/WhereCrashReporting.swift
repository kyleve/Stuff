/// A process-wide crash-reporting tool started during application launch.
@MainActor
public protocol WhereCrashReporting {
    func start()
}
