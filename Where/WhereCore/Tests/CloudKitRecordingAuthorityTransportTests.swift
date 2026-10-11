import CloudKit
import Foundation
import Testing
@testable import WhereCore

struct CloudKitRecordingAuthorityTransportTests {
    @Test func onlyTemporaryTransportFailuresPermitOfflineUse() {
        #expect(CloudKitRecordingAuthorityTransport
            .isTemporarilyUnavailable(CKError(.networkUnavailable)))
        #expect(!CloudKitRecordingAuthorityTransport
            .isTemporarilyUnavailable(CKError(.notAuthenticated)))
        #expect(!CloudKitRecordingAuthorityTransport
            .isTemporarilyUnavailable(RecordingAuthorityError.invalidRecord))
    }
}
