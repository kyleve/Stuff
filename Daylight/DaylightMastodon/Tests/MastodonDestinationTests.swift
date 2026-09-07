import CoreImage
import DaylightCore
@testable import DaylightMastodon
import Foundation
import Testing

struct MastodonDestinationTests {
    @Test func connectsDisabledAndRejectsUnsafeURLs() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: folder) } catch { Issue.record(error) }
        }
        let transport = ScriptedHTTPTransport([.init(
            data: Data(#"{"id":"123","acct":"camera"}"#.utf8),
            status: 200,
            retryAfter: nil,
        )])
        let destination = MastodonDestination(
            settingsURL: folder.appendingPathComponent("settings.json"),
            transport: transport,
            credentials: MemoryCredentials(),
            now: { Date(timeIntervalSince1970: 0) },
            uptime: { 0 },
        )
        let configuration = try await destination.connect(
            server: "https://example.com",
            token: "secret",
        )
        #expect(configuration.connection?.username == "camera")
        #expect(await destination.isEnabled() == false)
        await #expect(throws: MastodonError.self) { try await destination.connect(
            server: "http://example.com",
            token: "secret",
        ) }
        await #expect(throws: MastodonError.self) { try await destination.connect(
            server: "https://example.com/path",
            token: "secret",
        ) }
        #expect(await transport.requests.count == 1)
    }

    @Test func uploadPersistsCheckpointsAndReturnsReceipt() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: folder) } catch { Issue.record(error) }
        }
        let payloads = [
            #"{"id":"123","acct":"camera"}"#,
            #"{"configuration":{"media_attachments":{"image_size_limit":1000000,"image_matrix_limit":1000000,"supported_mime_types":["image/jpeg"]},"statuses":{"max_characters":500}}}"#,
            #"{"id":"42","url":null}"#,
            #"{"id":"42","url":"https://example.com/photo.jpg"}"#,
            #"{"id":"99","url":"https://example.com/@camera/99"}"#,
        ]
        let transport = ScriptedHTTPTransport(payloads.map { .init(
            data: Data($0.utf8),
            status: 200,
            retryAfter: nil,
        ) })
        let destination = MastodonDestination(
            settingsURL: folder.appendingPathComponent("settings.json"),
            transport: transport,
            credentials: MemoryCredentials(),
            now: { Date(timeIntervalSince1970: 0) },
            uptime: { 0 },
        )
        _ = try await destination.connect(server: "https://example.com", token: "secret")
        try await destination.update(
            enabled: true,
            visibility: .unlisted,
            caption: "{event} — {date}",
        )
        let url = folder.appendingPathComponent("image.jpg")
        let pixels = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        try JPEGRenderer().renderJPEG(pixels, maximumDimension: nil)
            .write(to: url)
        let event = SolarEvent(
            id: .init(year: 2026, month: 6, day: 21, kind: .sunset),
            date: Date(timeIntervalSince1970: 0),
        )
        let image = CapturedImage(
            id: .init(rawValue: UUID()),
            capturedAt: event.date,
            format: .jpeg,
        )
        let input = PublishingInput(
            kind: .sequenceHighlight,
            image: image,
            event: event,
            timeZoneIdentifier: "America/Los_Angeles",
            imageURL: url,
            rawURL: nil,
        )
        let checkpoint = CheckpointRecorder()
        let deliveryID = PublishingDelivery.ID(rawValue: UUID())
        let receipt = try await destination
            .deliver(input, deliveryID: deliveryID, checkpoint: nil) { await checkpoint.save($0) }
        #expect(receipt.remoteID == "99")
        #expect(await checkpoint.value != nil)
        let requests = await transport.requests
        #expect(requests.last?.value(forHTTPHeaderField: "Idempotency-Key") == deliveryID.rawValue
            .uuidString)
        #expect(requests.count == 5)
    }

    @Test func processingDelayResumesWithoutUploadingAgain() async throws {
        let fixture = try MastodonHarness(responses: [
            MastodonHarness.instance,
            MastodonHarness.uploaded,
            .init(data: Data(), status: 206, retryAfter: nil),
            MastodonHarness.processed,
            MastodonHarness.posted,
        ])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        try await fixture.connect()
        let input = try fixture.input()
        await #expect(throws: PublishingFailure.self) { try await fixture.deliver(input) }
        let receipt = try await fixture.deliver(input)
        #expect(receipt.remoteID == "99")
        let requests = await fixture.transport.requests
        #expect(requests.count(where: { $0.url?.path == "/api/v2/media" }) == 1)
        #expect(requests.count(where: { $0.url?.path == "/api/v1/statuses" }) == 1)
    }

    @Test(arguments: [401, 429, 503])
    func handlesAuthenticationAndRateLimits(status: Int) async throws {
        let fixture = try MastodonHarness(responses: [.init(
            data: Data(),
            status: status,
            retryAfter: "120",
        )])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        try await fixture.connect()
        do {
            _ = try await fixture.deliver(fixture.input())
            Issue.record("Request unexpectedly succeeded")
        } catch let failure as PublishingFailure {
            switch failure {
                case let .retry(after, _):
                    #expect(status != 401)
                    #expect(after == fixture.clock.now.addingTimeInterval(120))
                case .needsAttention: #expect(status == 401)
            }
        }
    }

    @Test func expiredAmbiguousSubmissionStopsBeforeNetwork() async throws {
        let fixture = try MastodonHarness(responses: [
            MastodonHarness.instance,
            MastodonHarness.uploaded,
            MastodonHarness.processed,
        ])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        try await fixture.connect()
        let input = try fixture.input()
        // The transport loses the response to the status submission.
        await #expect(throws: URLError.self) { try await fixture.deliver(input) }
        let count = await fixture.transport.requests.count
        fixture.clock.advance(3601)
        do {
            _ = try await fixture.deliver(input)
            Issue.record("Expired submission was retried")
        } catch let failure as PublishingFailure {
            if case .needsAttention = failure {} else { Issue.record("Expected reconciliation") }
        }
        #expect(await fixture.transport.requests.count == count)
    }

    @Test func mismatchedCredentialCannotSubmitThroughAnotherAccount() async throws {
        let fixture = try MastodonHarness(responses: [])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        try await fixture.connect()
        let configuration = await fixture.destination.configuration()
        let connection = try #require(configuration.connection)
        fixture.credentials.write(MastodonCredential(connection: .init(
            server: connection.server,
            accountID: "different-account",
            username: "different",
        ), token: "different-secret"))
        await #expect(throws: PublishingFailure.self) { try await fixture.deliver(fixture.input()) }
        #expect(await fixture.transport.requests.count == 1)
    }
}

extension MastodonDestinationTests {
    @Test func rechecksExpiryAfterMediaRequest() async throws {
        let fixture = try MastodonHarness(responses: [
            MastodonHarness.instance,
            MastodonHarness.uploaded,
            MastodonHarness.processed,
        ])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        try await fixture.connect()
        let input = try fixture.input()
        await #expect(throws: URLError.self) { try await fixture.deliver(input) }
        fixture.clock.advance(3490)
        await fixture.transport.replaceResponses([
            MastodonHarness.processed,
            MastodonHarness.posted,
        ]) { request in
            if request.url?.path == "/api/v1/media/42" { fixture.clock.advance(200) }
        }
        await #expect(throws: PublishingFailure.self) { try await fixture.deliver(input) }
        #expect(await fixture.transport.requests
            .count(where: { $0.url?.path == "/api/v1/statuses" }) == 1)
    }

    @Test func corruptConfigurationRemainsDisabledAndCanReconnectWithoutLosingEvidence(
    ) async throws {
        let fixture = try MastodonHarness(responses: [])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let url = fixture.root.appendingPathComponent("broken.json")
        let damaged = Data("invalid settings".utf8)
        try damaged.write(to: url)
        let destination = MastodonDestination(
            settingsURL: url,
            transport: fixture.transport,
            credentials: fixture.credentials,
            now: { fixture.clock.now },
            uptime: { fixture.clock.uptime },
        )
        #expect(await destination.configurationIssue() != nil)
        #expect(await destination.isEnabled() == false)
        await #expect(throws: MastodonError.self) { try await destination.update(
            enabled: true,
            visibility: .public,
            caption: "caption",
        ) }
        _ = try await destination.connect(server: "https://example.com", token: "secret")
        #expect(await destination.configurationIssue() == nil)
        #expect(await destination.isEnabled() == false)
        let backups = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil,
        ).filter { $0.lastPathComponent.hasPrefix("mastodon-invalid-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == damaged)
    }
}

extension MastodonDestinationTests {
    @Test func uncertainDeliveryCanBeExplicitlyReconciledWithoutBlindRetry() async throws {
        let fixture = try MastodonHarness(responses: [
            MastodonHarness.instance,
            MastodonHarness.uploaded,
            MastodonHarness.processed,
        ])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        try await fixture.connect()
        await #expect(throws: URLError.self) { try await fixture.deliver(fixture.input()) }
        fixture.clock.advance(3601)
        let checkpoint = try #require(await fixture.checkpoints.value)
        await #expect(throws: PublishingFailure.self) { try await fixture.destination.recover(
            checkpoint: checkpoint,
            action: .retry,
        ) }
        let result = try await fixture.destination.recover(
            checkpoint: checkpoint,
            action: .confirmedAbsent,
        )
        if case let .retry(checkpoint) = result {
            let retained = try #require(checkpoint)
            let object = try #require(JSONSerialization
                .jsonObject(with: retained) as? [String: Any])
            #expect(object["connection"] != nil)
            #expect(object["firstSubmission"] == nil)
        } else { Issue.record("Confirmed missing post was not released for retry") }
        let url = try #require(URL(string: "https://example.com/@camera/99"))
        let recorded = try await fixture.destination.recover(
            checkpoint: checkpoint,
            action: .published(url),
        )
        if case let .delivered(receipt) = recorded { #expect(receipt.remoteID == "99") }
        else { Issue.record("Existing post was not recorded") }
        let wrongServer = try #require(URL(string: "https://different.example/@camera/99"))
        await #expect(throws: PublishingFailure.self) { try await fixture.destination.recover(
            checkpoint: checkpoint,
            action: .published(wrongServer),
        ) }
    }
}

extension MastodonDestinationTests {
    @Test func confirmedRetryRefreshesCaptionWithoutChangingDeliveryIdentity() async throws {
        let fixture = try MastodonHarness(responses: [
            MastodonHarness.instance,
            MastodonHarness.uploaded,
            MastodonHarness.processed,
        ])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        try await fixture.connect()
        let input = try fixture.input()
        await #expect(throws: URLError.self) { try await fixture.deliver(input) }
        let recovered = try await fixture.destination.recover(
            checkpoint: fixture.checkpoints.value,
            action: .confirmedAbsent,
        )
        guard case let .retry(checkpoint) = recovered
        else { Issue.record("Expected retry"); return }
        try await fixture.destination.update(
            enabled: true,
            visibility: .private,
            caption: "Replacement {event}",
        )
        await fixture.transport.replaceResponses(
            [
                MastodonHarness.instance,
                MastodonHarness.uploaded,
                MastodonHarness.processed,
                MastodonHarness.posted,
            ],
            onRequest: { _ in },
        )
        _ = try await fixture.destination.deliver(
            input,
            deliveryID: fixture.deliveryID,
            checkpoint: checkpoint,
        ) { await fixture.checkpoints.save($0) }
        let request = try #require(await fixture.transport.requests.last)
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == fixture.deliveryID.rawValue
            .uuidString)
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["status"] as? String == "Replacement Sunset")
    }

    @Test func confirmedRetryRemainsBoundToOriginalAccount() async throws {
        let fixture = try MastodonHarness(responses: [
            MastodonHarness.instance,
            MastodonHarness.uploaded,
            MastodonHarness.processed,
        ])
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        try await fixture.connect()
        let input = try fixture.input()
        await #expect(throws: URLError.self) { try await fixture.deliver(input) }
        let recovered = try await fixture.destination.recover(
            checkpoint: fixture.checkpoints.value,
            action: .confirmedAbsent,
        )
        guard case let .retry(checkpoint) = recovered
        else { Issue.record("Expected retry"); return }
        await fixture.transport.replaceResponses(
            [MastodonHarness.response(#"{"id":"other","acct":"other"}"#)],
            onRequest: { _ in },
        )
        _ = try await fixture.destination.connect(
            server: "https://example.com",
            token: "other-token",
        )
        try await fixture.destination.update(
            enabled: true,
            visibility: .private,
            caption: "caption",
        )
        let count = await fixture.transport.requests.count
        await #expect(throws: PublishingFailure.self) {
            try await fixture.destination.deliver(
                input,
                deliveryID: fixture.deliveryID,
                checkpoint: checkpoint,
            ) { await fixture.checkpoints.save($0) }
        }
        #expect(await fixture.transport.requests.count == count)
    }
}
