@testable import Flagger
import SwiftData
import Testing

struct FlaggerPersistenceTests {
    @Test
    func mutationsReturnCompleteVersionedStoreSnapshots() async throws {
        let schema = Schema([FlagOverride.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let persistence = FlaggerPersistence(modelContainer: container)
        let firstID = FlagID(rawValue: "first")
        let secondID = FlagID(rawValue: "second")

        let first = try await persistence.persist(.boolean(true), for: firstID)
        #expect(first.revision == 1)
        #expect(first.values == [firstID: .boolean(true)])

        let second = try await persistence.persist(.string("value"), for: secondID)
        #expect(second.revision == 2)
        #expect(second.values == [
            firstID: .boolean(true),
            secondID: .string("value"),
        ])

        let removed = try await persistence.remove([firstID])
        #expect(removed.revision == 3)
        #expect(removed.values == [secondID: .string("value")])
    }
}
