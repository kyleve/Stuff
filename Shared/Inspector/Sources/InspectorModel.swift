import Foundation
import Observation

struct InspectorLoadedSwiftDataSource: Identifiable {
    let source: InspectorConfiguration.SwiftDataSource
    let model: InspectorSwiftDataModel

    var id: InspectorConfiguration.SwiftDataSource.ID {
        source.id
    }
}

actor InspectorSwiftDataLoader {
    func open(
        _ source: InspectorConfiguration.SwiftDataSource,
    ) throws -> InspectorSwiftDataStore {
        try InspectorSwiftDataStore(source: source)
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
    private(set) var fileSystem: InspectorFileSystem?

    private let loader = InspectorSwiftDataLoader()

    init(configuration: InspectorConfiguration) {
        self.configuration = configuration
    }

    func prepare() async {
        guard preparationState == .idle else { return }
        preparationState = .loading

        var protectedStoreURLs: [URL] = []
        var unresolvedProtectionRoots: [URL] = []

        for source in configuration.swiftDataSources {
            do {
                try Task.checkCancellation()
                let store = try await loader.open(source)
                let model = InspectorSwiftDataModel(
                    source: source,
                    store: store,
                )
                await model.loadEntities()
                await protectedStoreURLs.append(contentsOf: model.storeURLs())
                loadedSwiftDataSources[source.id] = InspectorLoadedSwiftDataSource(
                    source: source,
                    model: model,
                )
            } catch is CancellationError {
                preparationState = .idle
                return
            } catch {
                swiftDataFailures[source.id] = error.localizedDescription
                unresolvedProtectionRoots.append(source.storageRootURL)
            }
        }

        fileSystem = InspectorFileSystem(
            protectedStoreURLs: protectedStoreURLs,
            unresolvedProtectionRoots: unresolvedProtectionRoots,
        )
        preparationState = .ready
    }
}
