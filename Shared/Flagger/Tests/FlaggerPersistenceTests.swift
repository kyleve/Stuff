@testable import Flagger
import SwiftData
import Testing

struct FlaggerPersistenceTests {
    @Test
    func persistsAndDeletesAnOverrideExplicitly() async throws {
        let schema = Schema([FlagOverride.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let persistence = FlaggerPersistence(modelContainer: container)
        let id = FlagID(rawValue: "flag")

        _ = try await persistence.persist(.boolean(true), for: id)
        #expect(try await persistence.load()[id] == .boolean(true))

        _ = try await persistence.persist(nil, for: id)
        #expect(try await persistence.load()[id] == nil)
    }
}
