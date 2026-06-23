#if DEBUG
    import Foundation
    import SwiftData
    import SwiftUI

    /// A sample author row for inspector previews — has a to-many `books`
    /// relationship so the detail/relationship previews can drill into a graph.
    @Model
    final class InspectorPreviewAuthor {
        var name: String?
        var bio: String?
        @Relationship(deleteRule: .cascade, inverse: \InspectorPreviewBook.author)
        var books: [InspectorPreviewBook]?

        init(name: String?, bio: String?) {
            self.name = name
            self.bio = bio
            books = []
        }
    }

    /// A sample book row for inspector previews — spans the value kinds the
    /// formatter handles (text, date, count, flag, identifier, blob) plus a
    /// to-one `author` relationship.
    @Model
    final class InspectorPreviewBook {
        var id: UUID?
        var title: String?
        var pageCount: Int?
        var publishedAt: Date?
        var isAvailable: Bool?
        var cover: Data?
        var author: InspectorPreviewAuthor?

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
            let authors = [
                InspectorPreviewAuthor(name: "Ada Lovelace", bio: "Mathematician."),
                InspectorPreviewAuthor(name: "Alan Turing", bio: nil),
            ]
            for author in authors {
                context.insert(author)
            }
            for index in 1 ... 12 {
                let book = InspectorPreviewBook(
                    title: "The Long Title of Book Number \(index)",
                    pageCount: index * 37,
                    publishedAt: Date(timeIntervalSince1970: TimeInterval(index) * 86400),
                    isAvailable: index.isMultiple(of: 2),
                    cover: Data(count: index * 1024),
                )
                book.author = authors[index % authors.count]
                context.insert(book)
            }
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

        /// Drills into the first book's detail (which has a to-one `author`).
        @MainActor
        static func rowDetailPreview() -> some View {
            RowDetailPreviewHost(
                model: SwiftDataInspectorModel(configuration: populatedConfiguration()),
            )
        }

        /// Drills into an author's to-many `books` relationship.
        @MainActor
        static func relationshipPreview() -> some View {
            RelationshipPreviewHost(
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

    /// Loads entities and the first book row, then shows its detail so the
    /// `RowDetailView` preview renders against real fixtures.
    private struct RowDetailPreviewHost: View {
        let model: SwiftDataInspectorModel
        @State private var entity: InspectorEntity?
        @State private var row: InspectorRow?

        var body: some View {
            NavigationStack {
                if let entity, let row {
                    RowDetailView(model: model, entity: entity, row: row)
                } else {
                    ProgressView()
                }
            }
            .task {
                await model.loadEntities()
                guard let book = model.entities.first(where: { $0.name == "InspectorPreviewBook" })
                else {
                    return
                }
                entity = book
                row = await model.rows(for: book).rows.first
            }
        }
    }

    /// Loads entities and the first author row, then shows that author's to-many
    /// `books` relationship so the `RelationshipView` preview renders for real.
    private struct RelationshipPreviewHost: View {
        let model: SwiftDataInspectorModel
        @State private var entity: InspectorEntity?
        @State private var rowID: PersistentIdentifier?

        var body: some View {
            NavigationStack {
                if let entity, let rowID {
                    RelationshipView(
                        model: model,
                        sourceEntity: entity,
                        sourceRowID: rowID,
                        relationshipName: "books",
                    )
                } else {
                    ProgressView()
                }
            }
            .task {
                await model.loadEntities()
                guard let author = model.entities
                    .first(where: { $0.name == "InspectorPreviewAuthor" })
                else {
                    return
                }
                entity = author
                rowID = await model.rows(for: author).rows.first?.persistentID
            }
        }
    }
#endif
