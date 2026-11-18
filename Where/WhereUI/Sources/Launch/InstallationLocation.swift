import WhereCore

/// Installation-level permission and the real location source prepared before history opens.
/// Demo services have their own source and never contribute authorization to this owner.
@MainActor
public final class InstallationLocation {
    private let makeSource: @MainActor () -> any LocationSource
    private var preparedSource: (any LocationSource)?

    public init(makeSource: @escaping @MainActor () -> any LocationSource) {
        self.makeSource = makeSource
    }

    public static func live() -> InstallationLocation {
        InstallationLocation(makeSource: { CoreLocationSource() })
    }

    /// Synchronous preparation preserves queued background location events during admission.
    func prepare() {
        _ = source
    }

    /// The bootstrap and permission flow share this source. After retirement, a fresh source
    /// owns the next scope's stream; a canceled AsyncStream is never reused.
    var source: any LocationSource {
        if let preparedSource { return preparedSource }
        let source = makeSource()
        preparedSource = source
        return source
    }

    func authorization() async -> LocationAuthorizationStatus {
        await source.currentAuthorization()
    }

    func requestPermission() async throws {
        try await source.requestPermission()
    }

    func stop() async {
        await preparedSource?.stop()
    }

    func release() async {
        let source = preparedSource
        preparedSource = nil
        await source?.stop()
    }
}
