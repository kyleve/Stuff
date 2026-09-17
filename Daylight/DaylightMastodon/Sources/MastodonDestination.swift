import DaylightCore
import Foundation

/// One personal Mastodon account. Every remote checkpoint is persisted before the next side effect.
public actor MastodonDestination: PublishingDestination, MastodonManaging {
    public nonisolated let id = PublishingDestinationID(rawValue: "mastodon")
    public nonisolated let inputs: Set<PublishingInput.Kind> = [.sequenceHighlight]
    private let transport: any HTTPTransport
    private let credentials: any MastodonCredentials
    private let settingsURL: URL
    private enum ConfigurationState {
        case ready(MastodonSettings)
        case failed(String)
    }

    private var configurationState: ConfigurationState
    private var settings: MastodonSettings {
        switch configurationState {
            case let .ready(value): value
            case .failed: .initial
        }
    }

    private let uptime: @Sendable () -> TimeInterval
    private let now: @Sendable () -> Date
    private struct Account: Decodable { let id: String; let acct: String }
    private struct Media: Decodable { let id: String; let url: URL? }
    private struct Status: Decodable { let id: String; let url: URL }
    private struct Instance: Decodable {
        let configuration: Configuration
        struct Configuration: Decodable {
            let mediaAttachments: Limits
            let statuses: StatusLimits
        }

        struct Limits: Decodable {
            let imageSizeLimit: Int; let imageMatrixLimit: Int; let supportedMimeTypes: [String]
        }

        struct StatusLimits: Decodable { let maxCharacters: Int }
    }

    private struct Checkpoint: Codable {
        var version = 1
        let connection: MastodonSettings.Connection
        let caption: String
        let description: String
        let visibility: MastodonSettings.Visibility
        var mediaID: String?
        var firstSubmission: Date?
        var submissionClock: SubmissionClock?
        var refreshConfiguration: Bool?
    }

    public init(
        settingsURL: URL,
        transport: any HTTPTransport,
        credentials: any MastodonCredentials,
        now: @escaping @Sendable () -> Date,
        uptime: @escaping @Sendable () -> TimeInterval,
    ) {
        self.settingsURL = settingsURL; self.transport = transport; self
            .credentials = credentials; self.now = now
        self.uptime = uptime
        do {
            let value: MastodonSettings = if FileManager.default
                .fileExists(atPath: settingsURL.path)
            {
                try JSONDecoder().decode(MastodonSettings.self, from: Data(contentsOf: settingsURL))
            } else { .initial }
            guard value.version == 1 else { throw MastodonError.invalidResponse }
            configurationState = .ready(value)
        } catch {
            configurationState = .failed(error.localizedDescription)
        }
    }

    public func configurationIssue() -> String? {
        if case let .failed(message) = configurationState { return message }
        return nil
    }

    public func configuration() -> MastodonSettings {
        settings
    }

    public func isEnabled() -> Bool {
        settings.enabled && settings.connection != nil
    }

    public func connect(server value: String, token: String) async throws -> MastodonSettings {
        guard let components = URLComponents(string: value
            .trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme == "https", components.host != nil, components.user == nil,
            components.password == nil,
            components.query == nil, components.fragment == nil,
            ["", "/"].contains(components.path),
            let url = components.url else { throw MastodonError.invalidServer }
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { throw MastodonError.missingCredentials }
        let data = try await request(
            server: url,
            path: "api/v1/accounts/verify_credentials",
            token: secret,
            method: "GET",
            body: nil,
            contentType: nil,
            idempotencyKey: nil,
        )
        let account = try JSONDecoder().decode(Account.self, from: data)
        let connection = MastodonSettings.Connection(
            server: url,
            accountID: account.id,
            username: account.acct,
        )
        var updated = settings
        updated.connection = connection; updated.enabled = false
        try credentials.write(MastodonCredential(connection: connection, token: secret))
        try persist(updated)
        return updated
    }

    public func update(
        enabled: Bool,
        visibility: MastodonSettings.Visibility,
        caption: String,
    ) throws {
        guard case .ready = configurationState else { throw MastodonError.invalidResponse }
        guard !enabled || settings.connection != nil else { throw MastodonError.missingCredentials }
        var updated = settings
        updated.enabled = enabled; updated.visibility = visibility; updated.caption = caption
        try persist(updated)
    }

    private func persist(_ value: MastodonSettings) throws {
        if case .failed = configurationState,
           FileManager.default.fileExists(atPath: settingsURL.path)
        {
            let backup = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("mastodon-invalid-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        try JSONEncoder().encode(value).write(to: settingsURL, options: .atomic)
        configurationState = .ready(value)
    }

    public func deliver(
        _ input: PublishingInput,
        deliveryID: PublishingDelivery.ID,
        checkpoint: Data?,
        saveCheckpoint: @escaping @Sendable (Data) async throws
            -> Void,
    ) async throws -> PublishingReceipt {
        guard settings.enabled, let connection = settings.connection,
              let credential = try credentials.read()
        else { throw MastodonError.missingCredentials }
        guard credential.connection == connection else {
            throw PublishingFailure
                .needsAttention(
                    "Reconnect the displayed account before publishing. The saved token belongs to a different account.",
                )
        }
        let token = credential.token
        var progress: Checkpoint
        if let checkpoint {
            progress = try JSONDecoder().decode(Checkpoint.self, from: checkpoint)
            guard progress.version == 1, progress.connection == connection else {
                throw PublishingFailure
                    .needsAttention(
                        "The account changed. Review this queued post before publishing.",
                    )
            }
            if progress.refreshConfiguration == true {
                progress = try makeCheckpoint(input: input, connection: connection)
                try await saveCheckpoint(JSONEncoder().encode(progress))
            }
        } else {
            progress = try makeCheckpoint(input: input, connection: connection)
            try await saveCheckpoint(JSONEncoder().encode(progress))
        }
        try validateSubmission(progress)
        if progress.mediaID == nil {
            let instanceData = try await request(
                server: connection.server,
                path: "api/v2/instance",
                token: token,
                method: "GET",
                body: nil,
                contentType: nil,
                idempotencyKey: nil,
            )
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            let instance = try decoder.decode(Instance.self, from: instanceData)
            guard progress.caption.count <= instance.configuration.statuses.maxCharacters else {
                throw PublishingFailure
                    .needsAttention("Shorten the caption to fit this server's post limit.")
            }
            let limits = instance.configuration.mediaAttachments
            guard limits.supportedMimeTypes.contains("image/jpeg"), limits.imageSizeLimit > 0,
                  limits.imageMatrixLimit > 0
            else {
                throw PublishingFailure
                    .needsAttention("This server does not accept JPEG photographs.")
            }
            let source = try Data(contentsOf: input.imageURL)
            var dimension = min(2560, sqrt(Double(limits.imageMatrixLimit)))
            var jpeg = try JPEGExporter().stripMetadata(JPEGRenderer().renderJPEG(
                source,
                maximumDimension: dimension,
            ))
            while jpeg.count > limits.imageSizeLimit, dimension > 320 {
                dimension *= 0.75
                jpeg = try JPEGExporter().stripMetadata(JPEGRenderer().renderJPEG(
                    source,
                    maximumDimension: dimension,
                ))
            }
            guard jpeg.count <= limits.imageSizeLimit
            else {
                throw PublishingFailure
                    .needsAttention("The photograph cannot fit this server's upload limit.")
            }
            let boundary = UUID().uuidString
            let header = [
                "--\(boundary)",
                #"Content-Disposition: form-data; name="description""#,
                "",
                progress.description,
                "--\(boundary)",
                #"Content-Disposition: form-data; name="file"; filename="daylight.jpg""#,
                "Content-Type: image/jpeg",
                "",
                "",
            ].joined(separator: "\r\n")
            var body = Data(header.utf8)
            body.append(jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            let data = try await request(
                server: connection.server,
                path: "api/v2/media",
                token: token,
                method: "POST",
                body: body,
                contentType: "multipart/form-data; boundary=\(boundary)",
                idempotencyKey: nil,
            )
            progress.mediaID = try JSONDecoder().decode(Media.self, from: data).id
            try await saveCheckpoint(JSONEncoder().encode(progress))
        }
        guard let mediaID = progress.mediaID else { throw MastodonError.invalidResponse }
        let mediaData = try await request(
            server: connection.server,
            path: "api/v1/media/\(mediaID)",
            token: token,
            method: "GET",
            body: nil,
            contentType: nil,
            idempotencyKey: nil,
        )
        guard try JSONDecoder().decode(Media.self, from: mediaData).url != nil else {
            throw PublishingFailure.retry(
                after: now().addingTimeInterval(15),
                message: "Mastodon is processing the photo.",
            )
        }
        if progress.firstSubmission == nil {
            let date = now()
            progress.firstSubmission = date
            progress.submissionClock = SubmissionClock(date: date, uptime: uptime())
            try await saveCheckpoint(JSONEncoder().encode(progress))
        }
        struct Post: Encodable {
            let status: String; let media_ids: [String]; let visibility: String
        }
        let body = try JSONEncoder().encode(Post(
            status: progress.caption,
            media_ids: [mediaID],
            visibility: progress.visibility.rawValue,
        ))
        try Task.checkCancellation()
        try validateSubmission(progress)
        let data = try await request(
            server: connection.server,
            path: "api/v1/statuses",
            token: token,
            method: "POST",
            body: body,
            contentType: "application/json",
            idempotencyKey: deliveryID.rawValue.uuidString,
        )
        let status = try JSONDecoder().decode(Status.self, from: data)
        return PublishingReceipt(remoteID: status.id, url: status.url)
    }

    private func makeCheckpoint(
        input: PublishingInput,
        connection: MastodonSettings.Connection,
    ) throws -> Checkpoint {
        guard let zone = TimeZone(identifier: input.timeZoneIdentifier)
        else { throw MastodonError.invalidResponse }
        let date = input.image.capturedAt.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            timeZone: zone,
        ))
        let time = input.image.capturedAt.formatted(Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            timeZone: zone,
        ))
        let event = input.event.id.kind == .sunrise ? "Sunrise" : "Sunset"
        return Checkpoint(
            connection: connection,
            caption: settings.caption.replacingOccurrences(
                of: "{event}",
                with: event,
            ).replacingOccurrences(of: "{date}", with: date),
            description: "Camera view near \(event.lowercased()), photographed on \(date) at \(time).",
            visibility: settings.visibility,
        )
    }

    private func resetForRecovery(_ checkpoint: Checkpoint?) throws -> Data? {
        guard var checkpoint else { return nil }
        checkpoint.firstSubmission = nil
        checkpoint.submissionClock = nil
        checkpoint.mediaID = nil
        checkpoint.refreshConfiguration = true
        return try JSONEncoder().encode(checkpoint)
    }

    public func recover(
        checkpoint: Data?,
        action: PublishingRecoveryAction,
    ) throws -> PublishingRecoveryResult {
        guard let connection = settings.connection else { throw MastodonError.missingCredentials }
        let progress = try checkpoint.map { try JSONDecoder().decode(Checkpoint.self, from: $0) }
        if let progress {
            guard progress.version == 1, progress.connection == connection else {
                throw PublishingFailure
                    .needsAttention("Reconnect the original account to recover this delivery.")
            }
        }
        switch action {
            case .retry:
                if let progress, progress.firstSubmission != nil {
                    try validateSubmission(progress)
                    return .retry(checkpoint: checkpoint)
                }
                return try .retry(checkpoint: resetForRecovery(progress))
            case .confirmedAbsent:
                return try .retry(checkpoint: resetForRecovery(progress))
            case let .published(url):
                guard url.scheme == "https", url.host == connection.server.host,
                      url.port == connection.server.port, url.user == nil, url.password == nil,
                      url.query == nil, url.fragment == nil,
                      !url.lastPathComponent.isEmpty,
                      url.lastPathComponent.allSatisfy(\.isNumber)
                else {
                    throw PublishingFailure
                        .needsAttention(
                            "Enter the published post's URL on the original Mastodon server.",
                        )
                }
                return .delivered(PublishingReceipt(remoteID: url.lastPathComponent, url: url))
        }
    }

    private func validateSubmission(_ progress: Checkpoint) throws {
        guard progress.firstSubmission != nil else { return }
        guard let clock = progress.submissionClock else {
            throw PublishingFailure
                .needsAttention(
                    "Check Mastodon before retrying this older submission; its elapsed time cannot be verified.",
                )
        }
        try clock.validate(date: now(), uptime: uptime())
    }

    private func request(
        server: URL,
        path: String,
        token: String,
        method: String,
        body: Data?,
        contentType: String?,
        idempotencyKey: String?,
    ) async throws -> Data {
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        let response = try await transport.send(request)
        if response.status == 206 { throw PublishingFailure.retry(
            after: now().addingTimeInterval(15),
            message: "Mastodon is processing the photo.",
        ) }
        if response.status == 429 || response.status >= 500 {
            let retryDate: Date
            if let header = response.retryAfter, let seconds = Double(header), seconds.isFinite {
                retryDate = now().addingTimeInterval(max(1, seconds))
            } else if let header = response.retryAfter {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .gmt
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                retryDate = max(
                    now().addingTimeInterval(1),
                    formatter.date(from: header) ?? now().addingTimeInterval(60),
                )
            } else { retryDate = now().addingTimeInterval(60) }
            throw PublishingFailure.retry(
                after: retryDate,
                message: "Mastodon is temporarily unavailable (\(response.status)).",
            )
        }
        guard (200 ... 299).contains(response.status) else {
            throw PublishingFailure
                .needsAttention(
                    "Mastodon rejected the request (\(response.status)). Check the account, token permissions, and queued post.",
                )
        }
        return response.data
    }
}
