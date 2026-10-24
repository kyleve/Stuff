import Testing
@testable import ThrowCore
@testable import ThrowUI

struct AircraftSourceFailurePresentationTests {
    @Test func localNetworkDenialUsesActionablePresentationCategory() {
        #expect(
            AircraftSourceFailure.transport(.localNetworkDenied).presentationCategory ==
                .localNetworkDenied,
        )
    }

    @Test func ordinaryOfflineFailureRemainsGenericTransportCategory() {
        #expect(AircraftSourceFailure.transport(.offline).presentationCategory == .transport)
    }
}
