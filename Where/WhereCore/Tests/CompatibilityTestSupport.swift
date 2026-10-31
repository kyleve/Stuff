import CloudKit
@testable import WhereCore

actor CompatibilityTestTransport: RecordingAuthorityTransport {
    enum Availability { case online, offline, signedOut }
    private let base = LocalRecordingAuthorityTransport(now: { .now })
    private var availability: Availability = .online
    func setAvailability(_ value: Availability) {
        availability = value
    }

    private func check() throws {
        switch availability {
            case .online: return
            case .offline: throw CKError(.networkUnavailable)
            case .signedOut: throw CKError(.notAuthenticated)
        }
    }

    func current() async throws -> RecordingAuthorityCommit? {
        try check()
        return await base.current()
    }

    func fetchCommit(for eventID: RecordingAuthority
        .EventID) async throws -> RecordingAuthorityCommit?
    {
        try check()
        return await base.fetchCommit(for: eventID)
    }

    func commit(_ proposal: RecordingAuthorityProposal) async throws -> RecordingAuthorityCommit {
        try check()
        return try await base.commit(proposal)
    }
}
