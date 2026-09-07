import Foundation
import Testing
@testable import ThrowCore

struct HTTPTransportTests {
    @Test func localNetworkOfflineSignalMapsToPermissionDenial() {
        #expect(
            URLSessionHTTPTransport.category(
                for: .notConnectedToInternet,
                networkScope: .localNetwork,
            ) == .localNetworkDenied,
        )
    }

    @Test func cloudOfflineSignalRemainsProviderNeutralOfflineFailure() {
        #expect(
            URLSessionHTTPTransport.category(
                for: .notConnectedToInternet,
                networkScope: .internet,
            ) == .offline,
        )
    }

    @Test func canceledURLSessionErrorPreservesTaskCancellation() async {
        let task = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try URLSessionHTTPTransport.failure(
                for: URLError(.cancelled),
                networkScope: .internet,
            )
        }

        do {
            _ = try await task.value
            Issue.record("Expected task cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error).")
        }
    }

    @Test func uncanceledURLSessionCancellationRemainsATransportFailure() throws {
        #expect(
            try URLSessionHTTPTransport.failure(
                for: URLError(.cancelled),
                networkScope: .internet,
            ) == HTTPTransportFailure(category: .cancelled),
        )
    }

    @Test func descriptionsRedactCredentialCoordinatesReceiverURLAndBody() throws {
        let credentialSentinel = "credential-DO-NOT-LEAK-1234"
        let bodySentinel = "body-DO-NOT-LEAK"
        let coordinateSentinel = "37.1234"
        let receiverSentinel = "receiver.private.local"
        let request = try HTTPRequest(
            method: .get,
            url: #require(
                URL(string: "https://example.test/v2/lat/\(coordinateSentinel)/lon/-122/dist/5"),
            ),
            headers: [.rapidAPIKey: credentialSentinel],
            timeoutSeconds: 8,
        )
        let response = HTTPResponse(
            statusCode: 200,
            headers: ["Set-Cookie": credentialSentinel],
            data: Data(bodySentinel.utf8),
        )
        let credential = try AircraftCredential(secret: credentialSentinel)
        let source = ADSBExchangeRapidAPISource(
            transport: ScriptedHTTPTransport(outcomes: []),
            decoder: ADSBExchangeV2Decoder(),
            credential: credential,
            dateProvider: FixedDateProvider(date: ThrowCoreFixture.date),
        )
        let readsb = try ReadsbConfiguration(
            aircraftJSONURL: #require(
                URL(string: "http://\(receiverSentinel)/data/aircraft.json"),
            ),
        )
        let configured = try ConfiguredAircraftSource(
            source: source,
            baseCadence: AircraftPollingCadence(duration: .seconds(10)),
            metadataWarning: nil,
        )
        let values = [
            String(describing: request),
            String(reflecting: request),
            String(describing: response),
            String(reflecting: response),
            String(describing: credential),
            String(reflecting: credential),
            String(describing: source),
            String(reflecting: source),
            String(describing: configured),
            String(reflecting: configured),
            String(describing: readsb),
            String(reflecting: readsb),
            String(describing: AircraftSourceFailure.invalidCredential),
            String(reflecting: AircraftSourceFailure.invalidCredential),
        ]
        for value in values {
            #expect(value.contains(credentialSentinel) == false)
            #expect(value.contains(bodySentinel) == false)
            #expect(value.contains(coordinateSentinel) == false)
            #expect(value.contains(receiverSentinel) == false)
        }
    }

    @Test func cloudRedirectPolicyRejectsEveryRedirect() async throws {
        let delegate = CloudRedirectRejectingDelegate()
        let session = URLSession(configuration: .ephemeral)
        let originalURL = try #require(URL(string: "https://adsbexchange-com1.p.rapidapi.com/v2/"))
        let redirectedURL = try #require(URL(string: "https://attacker.invalid/collect"))
        let task = session.dataTask(with: originalURL)
        let response = try #require(
            HTTPURLResponse(
                url: originalURL,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": redirectedURL.absoluteString],
            ),
        )

        await confirmation { redirectHandled in
            delegate.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: redirectedURL),
            ) { redirectedRequest in
                #expect(redirectedRequest == nil)
                redirectHandled()
            }
        }
        task.cancel()
        session.invalidateAndCancel()
    }

    @Test(arguments: [
        "http://public.example/data/aircraft.json",
        "http://receiver.local/data/not-aircraft.json",
        "http://user:password@receiver.local/data/aircraft.json",
    ])
    func readsbRedirectPolicyRejectsInvalidTarget(rawURL: String) async throws {
        let originalURL = try #require(
            URL(string: "http://receiver.local/data/aircraft.json"),
        )
        let targetURL = try #require(URL(string: rawURL))
        let redirectedRequest = try await readsbRedirectResult(
            originalURL: originalURL,
            targetURL: targetURL,
        )
        #expect(redirectedRequest == nil)
    }

    @Test(arguments: [
        "http://another-receiver.local/data/aircraft.json",
        "https://public.example/data/aircraft.json",
    ])
    func readsbRedirectPolicyAllowsValidatedTarget(rawURL: String) async throws {
        let originalURL = try #require(
            URL(string: "http://receiver.local/data/aircraft.json"),
        )
        let targetURL = try #require(URL(string: rawURL))
        let redirectedRequest = try await readsbRedirectResult(
            originalURL: originalURL,
            targetURL: targetURL,
        )
        #expect(redirectedRequest?.url == targetURL)
    }

    @Test func readsbRedirectPolicyAllowsReceiverMetadataRedirectWithoutChangingKind() async throws {
        let originalURL = try #require(
            URL(string: "http://receiver.local/data/receiver.json"),
        )
        let validTargetURL = try #require(
            URL(string: "https://public.example/data/receiver.json"),
        )
        let changedKindURL = try #require(
            URL(string: "http://receiver.local/data/aircraft.json"),
        )

        let validRedirect = try await readsbRedirectResult(
            originalURL: originalURL,
            targetURL: validTargetURL,
        )
        let changedKindRedirect = try await readsbRedirectResult(
            originalURL: originalURL,
            targetURL: changedKindURL,
        )
        #expect(validRedirect?.url == validTargetURL)
        #expect(changedKindRedirect == nil)
    }

    private func readsbRedirectResult(
        originalURL: URL,
        targetURL: URL,
    ) async throws -> URLRequest? {
        let delegate = ReadsbRedirectValidatingDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: originalURL)
        let response = try #require(
            HTTPURLResponse(
                url: originalURL,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": targetURL.absoluteString],
            ),
        )

        let redirectedRequest = await withCheckedContinuation { continuation in
            delegate.urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: targetURL),
            ) { request in
                continuation.resume(returning: request)
            }
        }
        task.cancel()
        session.invalidateAndCancel()
        return redirectedRequest
    }
}
