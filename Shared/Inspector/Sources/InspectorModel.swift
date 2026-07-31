import Foundation
import Observation

struct InspectorLoadedSwiftDataSource: Identifiable {
    let source: InspectorConfiguration.SwiftDataSource
    let model: InspectorSwiftDataModel

    var id: InspectorConfiguration.SwiftDataSource.ID {
        source.id
    }
}

actor InspectorSwiftDataSourceWorker {
    enum Failure: LocalizedError {
        case eraseNotConfigured

        var errorDescription: String? {
            switch self {
                case .eraseNotConfigured:
                    "This source does not declare an on-disk store URL."
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func open(
        _ source: InspectorConfiguration.SwiftDataSource,
    ) throws -> InspectorSwiftDataStore {
        try InspectorSwiftDataStore(source: source)
    }

    /// Delete an unreadable source's configured store family as one serialized
    /// operation. Cancellation is honored only before erasure.
    func erase(
        _ source: InspectorConfiguration.SwiftDataSource,
    ) throws {
        guard let storeURL = source.storeURL else {
            throw Failure.eraseNotConfigured
        }
        let family = InspectorSwiftDataStoreFamily(
            storeURL: storeURL,
            storageRootURL: source.storageRootURL,
            recoveryStorageURLs: source.recoveryStorageURLs,
        )
        try family.erase(using: fileManager)
    }
}

@MainActor
@Observable
final class InspectorModel {
    enum PreparationState: Equatable {
        case idle
        case loading
        case ready
    }

    let configuration: InspectorConfiguration
    private(set) var preparationState = PreparationState.idle
    private(set) var loadedSwiftDataSources:
        [InspectorConfiguration.SwiftDataSource.ID: InspectorLoadedSwiftDataSource] = [:]
    private(set) var swiftDataFailures:
        [InspectorConfiguration.SwiftDataSource.ID: String] = [:]
    private(set) var erasingSwiftDataSources:
        Set<InspectorConfiguration.SwiftDataSource.ID> = []
    private(set) var removedSwiftDataSourceIDs:
        Set<InspectorConfiguration.SwiftDataSource.ID> = []
    private(set) var fileSystem: InspectorFileSystem?

    private let worker = InspectorSwiftDataSourceWorker()
    private let modeController: InspectorModeController

    init(
        configuration: InspectorConfiguration,
        modeController: InspectorModeController,
    ) {
        self.configuration = configuration
        self.modeController = modeController
    }

    var visibleSwiftDataSources: [InspectorConfiguration.SwiftDataSource] {
        configuration.swiftDataSources.filter {
            removedSwiftDataSourceIDs.contains($0.id) == false
        }
    }

    func prepare() async {
        guard preparationState == .idle else { return }
        preparationState = .loading

        for source in configuration.swiftDataSources {
            do {
                try Task.checkCancellation()
                let store = try await worker.open(source)
                let model = InspectorSwiftDataModel(
                    source: source,
                    store: store,
                )
                await model.loadEntities()
                loadedSwiftDataSources[source.id] = InspectorLoadedSwiftDataSource(
                    source: source,
                    model: model,
                )
            } catch is CancellationError {
                preparationState = .idle
                return
            } catch {
                swiftDataFailures[source.id] = error.localizedDescription
            }
        }

        await rebuildFileSystemProtection()
        preparationState = .ready
    }

    func canEraseUnreadableStore(id: InspectorConfiguration.SwiftDataSource.ID) -> Bool {
        swiftDataFailures[id] != nil
            && configuration.swiftDataSources.first(where: { $0.id == id })?.storeURL != nil
    }

    func eraseUnreadableStore(id: InspectorConfiguration.SwiftDataSource.ID) async -> Bool {
        guard canEraseUnreadableStore(id: id),
              let source = configuration.swiftDataSources.first(where: { $0.id == id }),
              let storeURL = source.storeURL,
              erasingSwiftDataSources.insert(id).inserted
        else {
            return false
        }
        defer { erasingSwiftDataSources.remove(id) }

        do {
            try await worker.erase(source)
            try modeController.scheduleStoreFamilyErasure(
                storeURL: storeURL,
                storageRootURL: source.storageRootURL,
                recoveryStorageURLs: source.recoveryStorageURLs,
            )
            loadedSwiftDataSources[id] = nil
            swiftDataFailures[id] = nil
            removedSwiftDataSourceIDs.insert(id)
            await rebuildFileSystemProtection()
            return true
        } catch is CancellationError {
            return false
        } catch {
            swiftDataFailures[id] = error.localizedDescription
            return false
        }
    }

    private func rebuildFileSystemProtection() async {
        var protectedStoreURLs: [URL] = []
        for loaded in loadedSwiftDataSources.values {
            let storeURLs = await loaded.model.storeURLs()
            protectedStoreURLs.append(contentsOf: storeURLs)
            protectedStoreURLs.append(contentsOf: loaded.source.recoveryStorageURLs)
        }
        let unresolvedProtectionRoots: [URL] = configuration.swiftDataSources.compactMap {
            source -> URL? in
            guard removedSwiftDataSourceIDs.contains(source.id) == false,
                  swiftDataFailures[source.id] != nil
            else {
                return nil
            }
            return source.storageRootURL
        }
        fileSystem = InspectorFileSystem(
            protectedStoreURLs: protectedStoreURLs,
            unresolvedProtectionRoots: unresolvedProtectionRoots,
        )
    }
}
