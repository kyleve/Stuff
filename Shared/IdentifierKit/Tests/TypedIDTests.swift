import Foundation
import IdentifierKit
import Testing

struct TypedIDTests {
    // No protocol conformances are required on the phantom owner, even Sendable.
    private final class Owner {}
    private enum RenamedOwner {}

    @Test func persistsAsABareUUIDAcrossOwnerRenames() throws {
        let uuid = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let identity = TypedID<Owner>(rawValue: uuid)
        let bytes = try JSONEncoder().encode(identity)
        #expect(try bytes == JSONEncoder().encode(uuid))
        #expect(try JSONDecoder().decode(TypedID<RenamedOwner>.self, from: bytes).rawValue == uuid)
    }

    @Test func rejectsMalformedIdentity() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TypedID<Owner>.self, from: Data("\"not-a-uuid\"".utf8))
        }
    }

    @Test func supportsSetMembershipAndDeterministicTies() throws {
        let first =
            try TypedID<Owner>(
                rawValue: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            )
        let second =
            try TypedID<Owner>(
                rawValue: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            )
        #expect(Set([first, second, first]).count == 2)
        #expect([second, first].sorted() == [first, second])
    }

    @Test func identityCanCrossActorsWithoutSendingItsOwner() async {
        let identity = TypedID<Owner>()
        let result = await Task.detached { identity }.value
        #expect(result == identity)
    }
}
