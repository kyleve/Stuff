import Foundation
import IndexStoreDB

/// File identities are checkout-relative, so metadata can move between CI workers.
struct SourcePath: Hashable, Codable, Comparable {
    let rawValue: String
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A compiler symbol identity, never inferred from a spelling in the source.
struct SymbolID: Hashable {
    let rawValue: String
}

struct IndexRequest: Decodable {
    let root: String
    let files: [String]
    let indexStore: String
    let database: String
    let library: String
}

struct IndexedFile: Encodable {
    let path: String
    let indexed: Bool
    let definitions: [String]
    let dependencies: [String]
    let syntax: SourceFacts
}

/// Exports conservative file references and local type relationships from a fresh build index.
struct IndexCollector {
    func collect(_ request: IndexRequest) throws -> [IndexedFile] {
        let root = URL(fileURLWithPath: request.root).standardizedFileURL
        let library = try IndexStoreLibrary(dylibPath: request.library)
        let index = try IndexStoreDB(
            storePath: request.indexStore,
            databasePath: request.database,
            library: library,
            waitUntilDoneInitializing: true,
            listenToUnitEvents: false,
        )
        index.pollForUnitChangesAndWait(isInitialScan: true)
        var occurrences: [SourcePath: [SymbolOccurrence]] = [:]
        var definitions: [SymbolID: Set<SourcePath>] = [:]
        for path in request.files {
            let source = SourcePath(rawValue: path)
            let values = index.symbolOccurrences(inFilePath: root.appendingPathComponent(path).path)
            occurrences[source] = values
            for occurrence in values where !occurrence.roles.intersection([
                .definition,
                .declaration,
            ]).isEmpty {
                definitions[SymbolID(rawValue: occurrence.symbol.usr), default: []].insert(source)
            }
        }

        // A member or extension can be reached through the nominal type (for example View.body).
        // Join only repository-owned types; joining every external SwiftUI.View conformer would
        // connect otherwise independent views through the system framework.
        var family: [SymbolID: Set<SourcePath>] = [:]
        for (file, values) in occurrences {
            for occurrence in values {
                // Swift indexes an extension as a reference to the original type,
                // related to a separate extension symbol. Its members are children
                // of that extension, not direct children of the original type.
                let symbol = SymbolID(rawValue: occurrence.symbol.usr)
                if occurrence.roles.contains(.extendedBy), definitions[symbol] != nil {
                    family[symbol, default: []].insert(file)
                }
                guard !occurrence.roles.intersection([.definition, .declaration]).isEmpty else {
                    continue
                }
                for relation in occurrence.relations
                    where !relation.roles.intersection([.childOf, .accessorOf]).isEmpty
                    && definitions[SymbolID(rawValue: relation.symbol.usr)] != nil
                {
                    family[SymbolID(rawValue: relation.symbol.usr), default: []].insert(file)
                }
            }
        }
        for (symbol, files) in family {
            definitions[symbol, default: []].formUnion(files)
        }

        return try request.files.sorted().map { path in
            let file = SourcePath(rawValue: path)
            let values = occurrences[file, default: []]
            var dependencies: Set<SourcePath> = []
            var declared: Set<String> = []
            for occurrence in values {
                let symbol = SymbolID(rawValue: occurrence.symbol.usr)
                dependencies.formUnion(definitions[symbol, default: []])
                for relation in occurrence.relations {
                    dependencies.formUnion(definitions[
                        SymbolID(rawValue: relation.symbol.usr),
                        default: [],
                    ])
                }
                if !occurrence.roles.intersection([.definition, .declaration]).isEmpty,
                   !occurrence.symbol.properties.contains(.local)
                {
                    declared.insert(symbol.rawValue)
                }
            }
            dependencies.remove(file)
            let fullPath = root.appendingPathComponent(path).path
            let modified = try URL(fileURLWithPath: fullPath)
                .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let indexedDate = index.dateOfLatestUnitFor(filePath: fullPath)
            let fresh = modified.flatMap { changed in indexedDate.map { $0 >= changed } } ?? false
            return try IndexedFile(
                path: path,
                indexed: fresh && !index.unitNamesContainingFile(path: fullPath).isEmpty,
                definitions: declared.sorted(),
                dependencies: dependencies.sorted().map(\.rawValue),
                syntax: .read(String(contentsOfFile: fullPath, encoding: .utf8)),
            )
        }
    }
}
