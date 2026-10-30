import Foundation
import InstallerKit
@testable import InstallerKitUI
import Testing

struct UpdateFailureDescriptionTests {
    @Test func missingFeedExplainsTheServerFailureInsteadOfSuggestingAConnectionProblem() {
        let failure = UpdateFailureDescription(error: UpdateClient.FetchError.httpStatus(404))
        #expect(failure.code == "HTTP 404")
        #expect(failure
            .message ==
            "The update feed was not found on the server. It may not have been published yet, or its address may have changed.")
    }

    @Test(arguments: [
        URLError.Code.notConnectedToInternet,
        .timedOut,
        .cannotFindHost,
        .secureConnectionFailed
    ])
    func explainsKnownTransportCodesEvenWithoutASystemDescription(_ code: URLError.Code) {
        let error = URLError(code)
        let failure = UpdateFailureDescription(error: error)
        #expect(failure.message != error.localizedDescription)
        #expect(!failure.message.contains("NSURLErrorDomain"))
        #expect(failure.code == "NSURLErrorDomain \(code.rawValue)")
    }

    @Test func offlineAndTimeoutHaveDifferentRecoveryAdvice() {
        let offline = UpdateFailureDescription(error: URLError(.notConnectedToInternet))
        let timeout = UpdateFailureDescription(error: URLError(.timedOut))
        #expect(offline
            .message == "This device is offline. Connect to the internet, then try again.")
        #expect(timeout.message == "The update server did not respond in time. Try again.")
    }

    @Test func distinguishesInvalidDataFromRejectedBuildInformation() {
        let decoding = UpdateFailureDescription(error: DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Untrusted response body",
        )))
        let validation = UpdateFailureDescription(error: UpdateCatalog.ValidationError
            .invalidCatalog)
        #expect(decoding.code == "DecodingError.dataCorrupted")
        #expect(validation.code == "InstallerKit.invalidCatalog")
        #expect(decoding.message != validation.message)
        #expect(!decoding.message.contains("Untrusted response body"))
    }

    @Test func unknownErrorsKeepTheirDescriptionAndDiagnosticIdentity() {
        let error = NSError(
            domain: "ExampleUpdateService",
            code: 73,
            userInfo: [NSLocalizedDescriptionKey: "The service is undergoing maintenance."],
        )
        let failure = UpdateFailureDescription(error: error)
        #expect(failure.message == error.localizedDescription)
        #expect(failure.code == "ExampleUpdateService 73")
    }
}
