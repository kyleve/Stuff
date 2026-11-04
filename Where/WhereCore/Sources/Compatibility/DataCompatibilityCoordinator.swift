import CloudKit
import Foundation
import Observation

/// Owns account verification and admitted scope lifetimes. A failed refresh may retain verified
/// access to the same binding; unknown identity and known incompatibility revoke it immediately.
@MainActor
@Observable
public final class DataCompatibilityCoordinator {
    public enum Source {
        case local(storeID: DataCompatibilityDataset.StoreID)
        case cloudKit(
            storeID: DataCompatibilityDataset.StoreID,
            transport: any SharedDataCompatibilityTransport,
            cache: any DataCompatibilityCacheStoring,
        )
    }

    public enum Synchronization {
        case verified
        case uncertain(any Error)
    }

    public enum State {
        case unknown
        case available(DataCompatibilityAccess, Synchronization)
        case updateRequired(requiredMajor: UInt)
        case failed(any Error)
    }

    public enum ActivationReadiness { case pendingValidation, ready }
    public enum UpgradeAuthorization {
        case recentContribution(
            deviceID: RecordingDeviceID,
            contributions: [RecordingHistoryContribution],
        )
        case confirmedByUser
    }

    private final class Attempt {}

    public private(set) var state: State = .unknown
    public private(set) var knownRequiredMajor: UInt = 0
    public let policy: DataCompatibilityPolicy
    @ObservationIgnored private let store: any WhereStore
    @ObservationIgnored private let source: Source
    @ObservationIgnored private let activationReadiness: ActivationReadiness
    @ObservationIgnored private var identifiedAccount: DataCompatibilityAccountID?
    @ObservationIgnored private var cached: DataCompatibilityCache?
    /// Same-process proof can survive a network failure while disk admission is invalidated
    /// for an outstanding read. A storage failure discards this proof.
    @ObservationIgnored private var offlineProof: DataCompatibilityCache?
    @ObservationIgnored private var pendingVerifications: Set<ObjectIdentifier> = []
    @ObservationIgnored private var attempt: Attempt?
    /// A server mutation remains in flight even if an account event supersedes its caller.
    /// No verification that races that mutation may grant an older scope.
    @ObservationIgnored private var activationInFlight: Attempt?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?

    public init(
        store: any WhereStore,
        source: Source,
        policy: DataCompatibilityPolicy,
        activationReadiness: ActivationReadiness,
    ) {
        self.store = store
        self.source = source
        self.policy = policy
        self.activationReadiness = activationReadiness
    }

    deinit {
        accountTask?.cancel()
        importTask?.cancel()
        recoveryTask?.cancel()
    }

    public var access: DataCompatibilityAccess? {
        if case let .available(access, _) = state { access } else { nil }
    }

    public func startObserving() {
        if importTask == nil {
            let changes = store.remoteChanges()
            importTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    await self?.recheckLocalRequirements()
                }
            }
        }
        if accountTask == nil, case let .cloudKit(_, transport, _) = source {
            let changes = transport.accountChanges()
            accountTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    self?.invalidateAccount()
                }
            }
        }
    }

    /// Call at launch and foreground/background activation. Superseded completions can raise
    /// known requirements but cannot restore an invalidated scope.
    @discardableResult
    public func refresh() async throws -> DataCompatibilityAccess {
        guard activationInFlight == nil else { throw DataCompatibilityError.verificationRequired }
        let request = Attempt()
        attempt = request
        defer { pendingVerifications.remove(ObjectIdentifier(request)) }
        do {
            let local = try await store.dataCompatibilityState()
            if local.persistedRequiredMajor != nil || !local.recordMajors.isEmpty {
                observeRequiredMajor(local.requiredMajor)
            }
            try requireCurrent(request)
            try local.validate(policy: policy)
            if knownRequiredMajor > 0 || local.persistedRequiredMajor != nil {
                try policy.validate(requiredMajor: knownRequiredMajor)
            }
            switch source {
                case .local:
                    if local.persistedRequiredMajor == nil {
                        let initialMajor = local.hasLegacyHistory ? 0 : policy.current.major
                        try await persistRequirement(max(knownRequiredMajor, initialMajor))
                    }
                    try requireCurrent(request)
                    return try makeAccess(synchronization: .verified)
                case let .cloudKit(storeID, transport, cache):
                    let loaded = try cache.load()
                    cached = loaded?.storeID == storeID ? loaded : nil
                    if let cached {
                        observeRequiredMajor(cached.requiredMajor)
                        if cached.verified,
                           cached.requiredMajor >= knownRequiredMajor { offlineProof = cached }
                    }
                    if cached != nil || knownRequiredMajor > 0 {
                        try policy.validate(requiredMajor: knownRequiredMajor)
                    }
                    let accountID = try await transport.accountID()
                    try requireCurrent(request)
                    if let cached, cached.storeID == storeID, cached.accountID != accountID {
                        throw DataCompatibilityError.accountChanged
                    }
                    identifiedAccount = accountID
                    try beginSharedVerification(request, accountID: accountID)
                    let verification = try await transport.verify(accountID: accountID)
                    guard verification.accountID == accountID else {
                        throw DataCompatibilityError.accountChanged
                    }
                    let shared: SharedDataCompatibilityState
                    switch verification.history {
                        case let .existing(value): shared = value
                        case .legacyAccount, .newAccount:
                            try requireCurrent(request)
                            shared = try await transport.initialize(
                                accountID: accountID,
                                newAccountMajor: local
                                    .hasLegacyHistory && cached == nil ? 0 : policy.current.major,
                            )
                    }
                    guard shared.accountID == accountID
                    else { throw DataCompatibilityError.accountChanged }
                    try rememberSharedRequirement(accountID: accountID, major: shared.requiredMajor)
                    try requireCurrent(request)
                    try policy.validate(requiredMajor: knownRequiredMajor)
                    pendingVerifications.remove(ObjectIdentifier(request))
                    let saved = DataCompatibilityCache(
                        storeID: storeID,
                        accountID: accountID,
                        requiredMajor: knownRequiredMajor,
                        verified: pendingVerifications.isEmpty,
                    )
                    try cache.save(saved)
                    cached = saved
                    offlineProof = DataCompatibilityCache(
                        storeID: storeID,
                        accountID: accountID,
                        requiredMajor: knownRequiredMajor,
                        verified: true,
                    )
                    return try makeAccess(synchronization: .verified)
            }
        } catch {
            pendingVerifications.remove(ObjectIdentifier(request))
            guard attempt === request else {
                // A newer verified scope may have waited for this final older read to drain.
                // Restore only its current proof, never the superseded response's grant.
                if pendingVerifications.isEmpty, hasValidOfflineProof {
                    do { try persistOfflineGrant() }
                    catch { offlineProof = nil; block(error); throw error }
                }
                throw error
            }
            if (error as? CKError)?.code == .notAuthenticated ||
                (error as? DataCompatibilityError) == .accountChanged
            {
                invalidateAccount()
                block(error)
                throw error
            }
            if canUseCache(after: error) {
                do {
                    try persistOfflineGrant()
                    return try makeAccess(synchronization: .uncertain(error))
                } catch {
                    offlineProof = nil
                    block(error)
                    throw error
                }
            }
            offlineProof = nil
            block(error)
            throw error
        }
    }

    public func invalidateAccount() {
        attempt = nil
        access?.revoke()
        identifiedAccount = nil
        offlineProof = nil
        state = .failed(DataCompatibilityError.verificationRequired)
        do { try invalidateCachedVerification() }
        catch { state = .failed(error) }
    }

    private func invalidateCachedVerification() throws {
        guard case let .cloudKit(storeID, _, cache) = source,
              let cached = try cache.load(), cached.storeID == storeID else { return }
        let invalidated = DataCompatibilityCache(
            storeID: cached.storeID,
            accountID: cached.accountID,
            requiredMajor: max(cached.requiredMajor, knownRequiredMajor),
            verified: false,
        )
        self.cached = invalidated
        try cache.save(invalidated)
    }

    /// An explicit or eligible automatic activation always verifies shared state online first.
    /// A lost save response remains uncertain; refresh must resolve it before another attempt.
    public func activateCurrentMajor(
        authorization: UpgradeAuthorization,
        now: Date,
    ) async throws -> DataCompatibilityAccess {
        guard activationInFlight == nil else { throw DataCompatibilityError.verificationRequired }
        guard activationReadiness == .ready else { throw DataCompatibilityError.activationNotReady }
        if case .cloudKit = source {
            switch authorization {
                case .confirmedByUser: break
                case let .recentContribution(deviceID, contributions):
                    guard DataCompatibilityUpgradeEligibility.qualifies(
                        deviceID: deviceID,
                        contributions: contributions,
                        now: now,
                    ) else { throw DataCompatibilityError.upgradeRequiresConfirmation }
            }
        }
        let request = Attempt()
        activationInFlight = request
        defer { if activationInFlight === request { activationInFlight = nil } }
        attempt = request
        access?.revoke()
        state = .unknown
        offlineProof = nil
        do {
            // Load and durably invalidate even on a coordinator that has never refreshed. A lost
            // save response must not leave a reusable older grant, including after process death.
            try invalidateCachedVerification()
            switch source {
                case .local:
                    try await persistRequirement(max(knownRequiredMajor, policy.current.major))
                case let .cloudKit(_, transport, _):
                    let accountID = try await transport.accountID()
                    try requireCurrent(request)
                    if let identifiedAccount, identifiedAccount != accountID {
                        invalidateAccount()
                        throw DataCompatibilityError.accountChanged
                    }
                    if let cached, cached.accountID != accountID {
                        invalidateAccount()
                        throw DataCompatibilityError.accountChanged
                    }
                    let verification = try await transport.verify(accountID: accountID)
                    try requireCurrent(request)
                    let current: SharedDataCompatibilityState = switch verification.history {
                        case let .existing(value): value
                        case .legacyAccount, .newAccount:
                            try await transport.initialize(
                                accountID: accountID,
                                newAccountMajor: policy.current.major,
                            )
                    }
                    try rememberSharedRequirement(
                        accountID: accountID,
                        major: current.requiredMajor,
                    )
                    try requireCurrent(request)
                    try policy.validate(requiredMajor: knownRequiredMajor)
                    let confirmed = try await transport.advance(
                        from: current,
                        to: max(knownRequiredMajor, policy.current.major),
                    )
                    try rememberSharedRequirement(
                        accountID: accountID,
                        major: confirmed.requiredMajor,
                    )
                    try requireCurrent(request)
            }
            try requireCurrent(request)
        } catch {
            if attempt === request { block(error) }
            throw error
        }
        activationInFlight = nil
        // Refresh also persists the account binding and replaces an older-major scope.
        return try await refresh()
    }

    private func recheckLocalRequirements() async {
        let shouldRefresh: Bool
        do {
            let local = try await store.dataCompatibilityState()
            guard local.persistedRequiredMajor != nil || !local.recordMajors.isEmpty else { return }
            let previousAccess = access
            if local.persistedRequiredMajor != nil || !local.recordMajors.isEmpty {
                observeRequiredMajor(local.requiredMajor)
            }
            if let accountID = identifiedAccount {
                try rememberSharedRequirement(accountID: accountID, major: local.requiredMajor)
            }
            try local.validate(policy: policy)
            try policy.validate(requiredMajor: knownRequiredMajor)
            shouldRefresh = previousAccess != nil && previousAccess?
                .requiredMajor != knownRequiredMajor
        } catch { block(error); return }
        if shouldRefresh { await refreshAfterImport() }
    }

    /// Observing a requirement and granting access are different operations. Persist knowledge
    /// even when the request that learned it was superseded; preserve the old verification bit.
    /// This cache is device-local and account-bound, so no queued mirror write can carry a floor
    /// from the previous account into a newly signed-in account.
    private func rememberSharedRequirement(
        accountID: DataCompatibilityAccountID,
        major: UInt,
    ) throws {
        guard case let .cloudKit(storeID, _, cache) = source else { return }
        observeRequiredMajor(major)
        let loaded = try cache.load()
        let previous = loaded?.storeID == storeID ? loaded : nil
        if let previous, previous.accountID != accountID {
            throw DataCompatibilityError.accountChanged
        }
        observeRequiredMajor(max(major, previous?.requiredMajor ?? 0))
        let saved = DataCompatibilityCache(
            storeID: storeID,
            accountID: accountID,
            requiredMajor: knownRequiredMajor,
            verified: previous?.storeID == storeID && previous?.verified == true,
        )
        try cache.save(saved)
        cached = saved
    }

    private func beginSharedVerification(
        _ request: Attempt,
        accountID: DataCompatibilityAccountID,
    ) throws {
        pendingVerifications.insert(ObjectIdentifier(request))
        guard case let .cloudKit(storeID, _, cache) = source,
              let previous = try cache.load(), previous.storeID == storeID else { return }
        guard previous.accountID == accountID else { throw DataCompatibilityError.accountChanged }
        let invalidated = DataCompatibilityCache(
            storeID: storeID,
            accountID: accountID,
            requiredMajor: max(previous.requiredMajor, knownRequiredMajor),
            verified: false,
        )
        try cache.save(invalidated)
        cached = invalidated
    }

    private func persistOfflineGrant() throws {
        guard case let .cloudKit(_, _, cache) = source, let offlineProof else {
            throw DataCompatibilityError.verificationRequired
        }
        let saved = DataCompatibilityCache(
            storeID: offlineProof.storeID,
            accountID: offlineProof.accountID,
            requiredMajor: knownRequiredMajor,
            verified: pendingVerifications.isEmpty,
        )
        try cache.save(saved)
        cached = saved
    }

    private func persistRequirement(_ major: UInt) async throws {
        try await store.perform { try await self.store.raiseRequiredDataMajor(major) }
        let local = try await store.dataCompatibilityState()
        observeRequiredMajor(local.requiredMajor)
    }

    private func requireCurrent(_ request: Attempt) throws {
        guard attempt === request else { throw DataCompatibilityError.verificationRequired }
        try Task.checkCancellation()
    }

    private func makeAccess(synchronization: Synchronization) throws -> DataCompatibilityAccess {
        try policy.validate(requiredMajor: knownRequiredMajor)
        if let access, access.requiredMajor == knownRequiredMajor {
            do {
                try access.validate()
                state = .available(access, synchronization)
                return access
            } catch {
                // A verified refresh can replace a retired permit. A failed refresh cannot.
                if case .uncertain = synchronization { throw error }
            }
        }
        access?.revoke()
        let next = DataCompatibilityAccess(
            base: store,
            requiredMajor: knownRequiredMajor,
            policy: policy,
        ) { [weak self] error, accessID in
            Task { @MainActor in self?.observeFailure(error, accessID: accessID) }
        }
        state = .available(next, synchronization)
        return next
    }

    private func observeFailure(_ error: any Error, accessID: DataCompatibilityAccess.ID) {
        guard access?.id == accessID else { return }
        if case let DataCompatibilityError.updateRequired(major) = error,
           let accountID = identifiedAccount
        {
            do { try rememberSharedRequirement(accountID: accountID, major: major) }
            catch { block(error); return }
        }
        block(error)
        if (error as? DataCompatibilityError) == .verificationRequired {
            recoveryTask?.cancel()
            recoveryTask = Task { @MainActor [weak self] in await self?.refreshAfterImport() }
        }
    }

    #if DEBUG
        @_spi(Testing) public func waitForImportRecovery() async {
            await recoveryTask?.value
        }
    #endif

    private func refreshAfterImport() async {
        do { _ = try await refresh() }
        catch {
            // Refresh owns current-attempt state. A superseded completion must not revoke
            // the newer grant; the error remains observable in the compatibility log.
            WhereLog.root(DataCompatibilityLog.self).refreshFailed(error: .restricted(
                .errorDetails,
                error,
            ))
        }
    }

    private func observeRequiredMajor(_ major: UInt) {
        knownRequiredMajor = max(knownRequiredMajor, major)
        if let offlineProof,
           offlineProof.requiredMajor < knownRequiredMajor { self.offlineProof = nil }
        if !policy.supportedMajors.contains(knownRequiredMajor) {
            access?.revoke()
            state = .updateRequired(requiredMajor: knownRequiredMajor)
        } else if let access, access.requiredMajor != knownRequiredMajor {
            access.revoke()
            state = .unknown
        }
    }

    private func block(_ error: any Error) {
        access?.revoke()
        if case let DataCompatibilityError.updateRequired(major) = error {
            knownRequiredMajor = max(knownRequiredMajor, major)
            state = .updateRequired(requiredMajor: knownRequiredMajor)
        } else {
            state = .failed(error)
        }
    }

    private var hasValidOfflineProof: Bool {
        guard case let .cloudKit(storeID, _, _) = source,
              let offlineProof, offlineProof.verified,
              offlineProof.storeID == storeID,
              offlineProof.accountID == identifiedAccount,
              offlineProof.requiredMajor >= knownRequiredMajor,
              policy.supportedMajors.contains(knownRequiredMajor)
        else { return false }
        return true
    }

    private func canUseCache(after error: any Error) -> Bool {
        guard hasValidOfflineProof, let cloudError = error as? CKError else { return false }
        return [
            .networkUnavailable,
            .networkFailure,
            .serviceUnavailable,
            .requestRateLimited,
            .zoneBusy,
        ]
        .contains(cloudError.code)
    }
}
