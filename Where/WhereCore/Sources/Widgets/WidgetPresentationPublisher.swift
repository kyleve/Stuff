import PeriscopeCore
import WidgetKit

/// Publishes Where's device-local theme to the widget process without
/// rebuilding the independently stored data snapshot.
public actor WidgetPresentationPublisher {
    private let makeStore: @Sendable () throws -> WidgetPresentationStore
    private let reloadTimelines: @Sendable () -> Void
    private var lastPublishedTheme: WhereTheme?

    public init() {
        makeStore = { try WidgetPresentationStore.shared() }
        reloadTimelines = { WidgetCenter.shared.reloadAllTimelines() }
    }

    @_spi(Testing)
    public init(
        store: WidgetPresentationStore,
        reloadTimelines: @escaping @Sendable () -> Void,
    ) {
        makeStore = { store }
        self.reloadTimelines = reloadTimelines
    }

    /// Atomically publish the selected theme and ask WidgetKit to rebuild.
    /// Actor isolation serializes writes; the caller's cancellation check keeps
    /// a superseded model task from publishing after a newer selection.
    public func publish(_ theme: WhereTheme) {
        guard !Task.isCancelled, theme != lastPublishedTheme else { return }
        do {
            try makeStore().write(theme: theme)
            lastPublishedTheme = theme
            reloadTimelines()
            Self.logger.published(
                theme: .restricted(.technicalState, theme.rawValue),
            )
        } catch {
            Self.logger.publishFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "publish-error")],
            )
        }
    }

    private static let logger = WhereLog.widgets(WidgetPresentationPublisherLog.self)
}
