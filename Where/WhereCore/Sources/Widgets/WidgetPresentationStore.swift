import Foundation
import PeriscopeCore

/// Persists the widget extension's device-local presentation theme separately
/// from its aggregated data snapshot.
///
/// The app is the only writer. The widget reads this small App Group file when
/// building a timeline, defaulting to Standard when an older app version has
/// not written it yet or when a future/invalid value cannot be decoded.
public struct WidgetPresentationStore: Sendable {
    public struct AppGroupUnavailableError: Error {
        public init() {}
    }

    private static let fileName = "widget-presentation.json"

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared(appGroupIdentifier: String) throws -> WidgetPresentationStore {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier,
        ) else {
            throw AppGroupUnavailableError()
        }
        return WidgetPresentationStore(directory: container)
    }

    private var fileURL: URL {
        directory.appending(path: Self.fileName)
    }

    public func write(theme: WhereTheme) throws {
        let data = try JSONEncoder().encode(theme)
        try data.write(to: fileURL, options: .atomic)
    }

    public func readTheme() -> WhereTheme {
        guard let data = try? Data(contentsOf: fileURL) else { return .standard }
        do {
            return try JSONDecoder().decode(WhereTheme.self, from: data)
        } catch {
            Self.logger(attachments: [.error(error, name: "decode-error")]) {
                .unreadablePresentation(description: error.localizedDescription)
            }
            return .standard
        }
    }

    private static let logger = WhereLog.widgets(WidgetPresentationStoreLog.self)
}
