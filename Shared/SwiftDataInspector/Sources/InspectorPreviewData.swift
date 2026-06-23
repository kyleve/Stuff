#if DEBUG
    import Foundation
    import SwiftData
    import SwiftUI

    /// A sample author row for inspector previews.
    @Model
    final class InspectorPreviewAuthor {
        var name: String?
        var bio: String?

        init(name: String?, bio: String?) {
            self.name = name
            self.bio = bio
        }
    }

    /// A sample book row for inspector previews — spans the value kinds the
    /// formatter handles (text, date, count, flag, identifier, blob).
    @Model
    final class InspectorPreviewBook {
        var id: UUID?
        var title: String?
        var pageCount: Int?
        var publishedAt: Date?
        var isAvailable: Bool?
        var cover: Data?

        init(
            title: String?,
            pageCount: Int?,
            publishedAt: Date?,
            isAvailable: Bool?,
            cover: Data?,
        ) {
            id = UUID()
            self.title = title
            self.pageCount = pageCount
            self.publishedAt = publishedAt
            self.isAvailable = isAvailable
            self.cover = cover
        }
    }

    /// In-memory fixtures so the inspector previews standalone, without any host
    /// app or on-disk store.
    enum InspectorPreviewData {
        @MainActor
        static func populatedConfiguration() -> SwiftDataInspectorConfiguration {
            let container = makeContainer()
            let context = container.mainContext
            for index in 1 ... 12 {
                context.insert(InspectorPreviewBook(
                    title: "The Long Title of Book Number \(index)",
                    pageCount: index * 37,
                    publishedAt: Date(timeIntervalSince1970: TimeInterval(index) * 86400),
                    isAvailable: index.isMultiple(of: 2),
                    cover: Data(count: index * 1024),
                ))
            }
            context.insert(InspectorPreviewAuthor(name: "Ada Lovelace", bio: "Mathematician."))
            context.insert(InspectorPreviewAuthor(name: "Alan Turing", bio: nil))
            try? context.save()
            return SwiftDataInspectorConfiguration(container: container, title: "Library")
        }

        /// A store the inspector sees as having no model types, so the preview
        /// exercises the genuine "No Entities" empty state (rather than a schema
        /// whose tables merely happen to be empty).
        @MainActor
        static func emptyConfiguration() -> SwiftDataInspectorConfiguration {
            SwiftDataInspectorConfiguration(
                container: makeContainer(),
                modelTypes: [],
                title: "Library",
            )
        }

        @MainActor
        static func tablePreview() -> some View {
            TablePreviewHost(
                model: SwiftDataInspectorModel(configuration: populatedConfiguration()),
            )
        }

        @MainActor
        private static func makeContainer() -> ModelContainer {
            let schema = Schema([InspectorPreviewBook.self, InspectorPreviewAuthor.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // Previews can't recover from a broken in-memory store, so trap loudly.
            return try! ModelContainer(for: schema, configurations: [configuration])
        }
    }

    /// Loads the model's entities in a `.task` (now async) and then drills into
    /// the book table, so the table preview renders against real fixtures.
    private struct TablePreviewHost: View {
        let model: SwiftDataInspectorModel

        var body: some View {
            NavigationStack {
                if let entity = model.entities.first(where: { $0.name == "InspectorPreviewBook" })
                    ?? model.entities.first
                {
                    EntityTableView(model: model, entity: entity)
                } else {
                    ProgressView()
                }
            }
            .task { await model.loadEntities() }
        }
    }
#endif
