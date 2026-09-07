import CoreImage
import DaylightCore
@testable import DaylightMastodon
import Foundation
import Synchronization

actor ScriptedHTTPTransport: HTTPTransport {
    var responses: [HTTPResponse]
    var requests: [URLRequest] = []
    init(_ responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.cannotConnectToHost) }
        return responses.removeFirst()
    }
}

final class MemoryCredentials: MastodonCredentials {
    let token = Mutex<MastodonCredential?>(nil)
    func read() -> MastodonCredential? {
        token.withLock { $0 }
    }

    func write(_ value: MastodonCredential) {
        token.withLock { $0 = value }
    }
}

actor CheckpointRecorder {
    var value: Data?
    func save(_ data: Data) {
        value = data
    }
}

struct MastodonHarness {
    let root: URL
    let transport: ScriptedHTTPTransport
    let destination: MastodonDestination
    let clock = MastodonTestClock()
    let checkpoints = CheckpointRecorder()
    let credentials = MemoryCredentials()
    let deliveryID = PublishingDelivery.ID(rawValue: UUID())
    init(responses: [HTTPResponse]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        transport =
            ScriptedHTTPTransport([Self.response(#"{"id":"123","acct":"camera"}"#)] + responses)
        destination = try MastodonDestination(
            settingsURL: root.appendingPathComponent("settings.json"),
            transport: transport,
            credentials: credentials,
            now: { [clock] in clock.now },
        )
    }

    func connect() async throws {
        _ = try await destination.connect(server: "https://example.com", token: "secret")
        try await destination.update(enabled: true, visibility: .private, caption: "{event} {date}")
    }

    func input() throws -> PublishingInput {
        let url = root.appendingPathComponent("image.jpg")
        let pixels = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        try JPEGRenderer().renderJPEG(pixels, maximumDimension: nil)
            .write(to: url)
        let event = SolarEvent(
            id: .init(year: 2026, month: 6, day: 21, kind: .sunset),
            date: clock.now,
        )
        return PublishingInput(
            kind: .sequenceHighlight,
            image: CapturedImage(
                id: .init(rawValue: UUID()),
                capturedAt: clock.now,
                format: .jpeg,
            ),
            event: event,
            timeZoneIdentifier: "America/Los_Angeles",
            imageURL: url,
            rawURL: nil,
        )
    }

    func deliver(_ input: PublishingInput) async throws -> PublishingReceipt {
        try await destination
            .deliver(input, deliveryID: deliveryID, checkpoint: checkpoints.value) {
                await checkpoints.save($0)
            }
    }

    static func response(_ json: String) -> HTTPResponse {
        HTTPResponse(data: Data(json.utf8), status: 200, retryAfter: nil)
    }

    static let instance =
        response(
            #"{"configuration":{"media_attachments":{"image_size_limit":1000000,"image_matrix_limit":1000000,"supported_mime_types":["image/jpeg"]},"statuses":{"max_characters":500}}}"#,
        )
    static let uploaded = response(#"{"id":"42","url":null}"#)
    static let processed = response(#"{"id":"42","url":"https://example.com/photo.jpg"}"#)
    static let posted = response(#"{"id":"99","url":"https://example.com/@camera/99"}"#)
    func clean() throws {
        try FileManager.default.removeItem(at: root)
    }
}

final class MastodonTestClock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 10000))
    var now: Date {
        date.withLock { $0 }
    }

    func advance(_ seconds: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
