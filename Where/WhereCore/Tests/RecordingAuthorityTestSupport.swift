import Foundation
@testable import WhereCore

struct RecordingAuthorityFixture {
    let phone = RecordingDeviceID(rawValue: UUID())
    let tablet = RecordingDeviceID(rawValue: UUID())

    func proposal(
        _ state: RecordingAuthority,
        _ action: RecordingAuthorityProposal.Action,
        device: RecordingDeviceID,
        version: DataCompatibilityVersion = .initial,
    ) throws -> RecordingAuthorityProposal {
        try .init(
            state: state,
            action: action,
            deviceID: device,
            buildVersion: version,
            eventID: .init(rawValue: UUID()),
        )
    }
}
