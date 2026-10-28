import SwiftUI

extension View {
    /// Loads artwork from the injected cache with view-scoped cancellation.
    func regionArtworkTask<Key: Equatable, Artwork>(
        id: Key,
        model: RegionArtworkModel<Key, Artwork>,
        load: @escaping @MainActor (RegionOutlinePathCache) async -> Artwork?,
    ) -> some View {
        regionArtworkTask(id: id, displayKey: id, model: model, load: load)
    }

    /// A distinct display key keeps compatible artwork visible during a refresh,
    /// such as retaining region outlines while recorded location points change.
    func regionArtworkTask<Key: Equatable, Artwork>(
        id: some Equatable,
        displayKey: Key,
        model: RegionArtworkModel<Key, Artwork>,
        load: @escaping @MainActor (RegionOutlinePathCache) async -> Artwork?,
    ) -> some View {
        modifier(RegionArtworkTask(id: id, displayKey: displayKey, model: model, load: load))
    }
}

private struct RegionArtworkTask<ID: Equatable, Key: Equatable, Artwork>: ViewModifier {
    let id: ID
    let displayKey: Key
    let model: RegionArtworkModel<Key, Artwork>
    let load: @MainActor (RegionOutlinePathCache) async -> Artwork?

    @Environment(\.regionOutlinePathCache) private var cache

    private struct TaskIdentity: Equatable {
        let request: ID
        let displayKey: Key
        let cache: ObjectIdentifier?
    }

    func body(content: Content) -> some View {
        content.task(id: TaskIdentity(
            request: id,
            displayKey: displayKey,
            cache: cache.map(ObjectIdentifier.init),
        )) {
            await model.load(for: displayKey) {
                guard let cache else { return nil }
                return await load(cache)
            }
        }
    }
}
