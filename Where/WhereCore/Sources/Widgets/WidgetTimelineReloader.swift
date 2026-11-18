import WidgetKit

public protocol WidgetTimelineReloading: Sendable {
    func reload()
}

public struct WidgetCenterTimelineReloader: WidgetTimelineReloading {
    public init() {}
    public func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

public struct NoopWidgetTimelineReloader: WidgetTimelineReloading {
    public init() {}
    public func reload() {}
}
