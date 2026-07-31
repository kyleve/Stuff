import Foundation
import SwiftData

/// The app-owned resources that ``InspectorView`` may browse and mutate.
///
/// Inspector discovers nothing globally. The application names every file
/// container, defaults domain, and SwiftData source explicitly so previews and
/// tests remain hermetic and another app can reuse the tool without importing
/// app-specific code.
public struct InspectorConfiguration {
    public let title: String
    public let fileContainers: [FileContainer]
    public let defaultsDomains: [DefaultsDomain]
    public let swiftDataSources: [SwiftDataSource]

    public init(
        title: String,
        fileContainers: [FileContainer],
        defaultsDomains: [DefaultsDomain],
        swiftDataSources: [SwiftDataSource],
    ) {
        self.title = title
        self.fileContainers = fileContainers
        self.defaultsDomains = defaultsDomains
        self.swiftDataSources = swiftDataSources
    }
}

extension InspectorConfiguration {
    public struct FileContainer: Identifiable, Sendable {
        public struct ID: Hashable, RawRepresentable, Sendable {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public let id: ID
        public let title: String
        public let rootURL: URL

        public init(id: ID, title: String, rootURL: URL) {
            self.id = id
            self.title = title
            self.rootURL = rootURL.standardizedFileURL
        }
    }

    public struct DefaultsDomain: Identifiable {
        public struct ID: Hashable, RawRepresentable, Sendable {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public let id: ID
        public let title: String
        public let userDefaults: UserDefaults
        public let persistentDomainName: String

        public init(
            id: ID,
            title: String,
            userDefaults: UserDefaults,
            persistentDomainName: String,
        ) {
            self.id = id
            self.title = title
            self.userDefaults = userDefaults
            self.persistentDomainName = persistentDomainName
        }
    }

    public struct SwiftDataSource: Identifiable, Sendable {
        public struct ID: Hashable, RawRepresentable, Sendable {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public let id: ID
        public let title: String
        public let storageRootURL: URL
        /// The exact on-disk store URL. When present, Inspector may offer a
        /// confirmed store-family erase if the container cannot open.
        public let storeURL: URL?
        /// Additional durable files or directories that must be erased with
        /// an unreadable store for recovery to produce a genuinely fresh
        /// source. Every URL must be a strict descendant of
        /// ``storageRootURL``; Inspector deletes only these exact paths.
        public let recoveryStorageURLs: [URL]
        public let modelTypes: [any PersistentModel.Type]?
        public let rowLimit: Int?
        public let valueFormatter: (@Sendable (Any) -> String?)?
        let makeContainer: @Sendable () throws -> ModelContainer

        public init(
            id: ID,
            title: String,
            storageRootURL: URL,
            storeURL: URL? = nil,
            recoveryStorageURLs: [URL] = [],
            modelTypes: [any PersistentModel.Type]? = nil,
            rowLimit: Int? = 500,
            valueFormatter: (@Sendable (Any) -> String?)? = nil,
            makeContainer: @escaping @Sendable () throws -> ModelContainer,
        ) {
            self.id = id
            self.title = title
            self.storageRootURL = storageRootURL.standardizedFileURL
            self.storeURL = storeURL?.standardizedFileURL
            self.recoveryStorageURLs = recoveryStorageURLs.map(\.standardizedFileURL)
            self.modelTypes = modelTypes
            self.rowLimit = rowLimit
            self.valueFormatter = valueFormatter
            self.makeContainer = makeContainer
        }
    }
}
