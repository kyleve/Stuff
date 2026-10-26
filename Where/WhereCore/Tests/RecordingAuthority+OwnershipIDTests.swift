import Foundation
import Testing
@testable import WhereCore

struct RecordingAuthorityOwnershipIDTests {
    @Test func existingEventURLsRetainTheirWireSpellingInTheNewRole() throws {
        let json = Data(#""store://recording-authority/00000000-0000-0000-0000-000000000001""#.utf8)
        let value = try JSONDecoder().decode(RecordingAuthority.OwnershipID.self, from: json)
        let event = RecordingAuthority.EventID(rawValue: value.rawValue)
        #expect(value == RecordingAuthority.OwnershipID(eventID: event))
        let encoded = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(String.self, from: encoded) ==
            JSONDecoder().decode(String.self, from: json))
    }

    @Test(arguments: [
        "store://devices/00000000-0000-0000-0000-000000000001",
        "store://recording-authority/not-a-uuid",
    ])
    func malformedOrUnrelatedIdentityDoesNotDecode(_ value: String) throws {
        let data = try JSONEncoder().encode(value)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RecordingAuthority.OwnershipID.self, from: data)
        }
    }
}
