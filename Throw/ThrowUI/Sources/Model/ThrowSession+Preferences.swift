import Foundation
import ThrowCore

extension ThrowSession {
    func apply(_ preferences: ThrowPreferences) {
        setupState = preferences.setupState
        projectionPlaylist = preferences.playlist
        let coordinator = ProjectionExperienceCoordinatorState(
            playlist: preferences.playlist,
        )
        globalPreferences = preferences.global
        airAndSpacePreferences = preferences.airAndSpace
        calibrationPreview = nil
        locationHealth = Self.locationHealth(
            for: preferences.confirmedLocation,
            now: dateProvider.now(),
        )
        mayApplyTrueHeadingHint = preferences.setupCompleted == false
            && preferences.calibration == .defaultValue
        pendingAirAndSpaceFrame = .empty
        projectionContextGeneration = projectionContextGeneration.successor()
        revokeStagedProjection()
        projectionInputRevision = projectionInputRevision.successor()
        projectionPresentationState = .initial(
            coordinator: coordinator,
            preferredExperienceID: preferences.playlist.selectedExperienceID ?? .airAndSpace,
            mode: projectionMode,
            generatedAt: dateProvider.now(),
        )
    }

    public func updateProjectionMode(_ projectionMode: ProjectionMode) {
        guard self.projectionMode != projectionMode else { return }
        setupState = setupState.updatingProjectionMode(projectionMode)
        projectionInputsChanged(restartsPolling: true)
    }

    public func updateGlobalPreferences(_ preferences: ThrowGlobalPreferences) {
        let previous = globalPreferences
        guard previous != preferences else { return }

        let calibrationChanged = previous.calibration != preferences.calibration
        let quietScheduleChanged = previous.quietSchedule != preferences.quietSchedule
        globalPreferences = preferences
        calibrationPreview = nil
        if calibrationChanged,
           previous.calibration.screenTopBearing != preferences.calibration.screenTopBearing
        {
            mayApplyTrueHeadingHint = false
        }

        schedulePreferencesSave(failure: .preferencePersistence)
        if calibrationChanged {
            rebuildCurrentLayerFrame()
            restartRenderer()
        }
        if quietScheduleChanged {
            scheduleDemandReconciliation()
        }
    }

    public func updateAirAndSpacePreferences(_ preferences: AirAndSpacePreferences) {
        let previous = airAndSpacePreferences
        guard previous != preferences else { return }

        let queryInputsChanged = previous.mapViewport != preferences.mapViewport
            || previous.mapCenters != preferences.mapCenters
            || previous.skyViewport != preferences.skyViewport
            || previous.flightsEnabled != preferences.flightsEnabled
            || previous.includeGroundAircraft != preferences.includeGroundAircraft
        let labelModeChanged = previous.labelMode != preferences.labelMode
        let geographyVisibilityChanged = previous.geography.isEnabled
            != preferences.geography.isEnabled
        airAndSpacePreferences = preferences

        if previous.geography.isEnabled, preferences.geography.isEnabled == false {
            removeVisibleGeography()
        }

        schedulePreferencesSave(failure: .preferencePersistence)
        if labelModeChanged {
            rebuildCurrentLayerFrame()
        }
        if queryInputsChanged ||
            (geographyVisibilityChanged && preferences.flightsEnabled == false)
        {
            scheduleDemandReconciliation()
        } else if labelModeChanged || geographyVisibilityChanged {
            restartRenderer()
        }
    }

    func projectionInputsChanged(restartsPolling: Bool) {
        schedulePreferencesSave(failure: .preferencePersistence)
        if restartsPolling {
            scheduleDemandReconciliation()
        } else {
            rebuildCurrentLayerFrame()
            restartRenderer()
        }
    }

    private func removeVisibleGeography() {
        let visible = visibleProjection.removingGeography()
        guard let presentation = projectionPresentationState.replacingVisible(visible) else {
            assertionFailure("Removing geography must preserve the visible View")
            return
        }
        projectionPresentationState = presentation
    }

    func schedulePreferencesSave(failure: ThrowPostLaunchFailure) {
        guard preferencePersistence.isMutationActive == false else {
            preferencePersistence.recordDeferredFailure(failure)
            return
        }
        let preferences: ThrowPreferences
        do {
            preferences = try makePreferences()
        } catch {
            recordPostLaunchFailure(failure, error: error)
            return
        }
        if preferencePersistence.lastRequestIsCoalescible {
            preferencePersistence.coalesceLastRequest(
                with: preferences,
                failure: failure,
            )
        } else {
            enqueuePreferenceSave(
                .coalesced(
                    preferences,
                    failureLedger: ThrowPostLaunchFailureLedger().recording(failure),
                ),
            )
        }
    }

    func savePreferencesImmediately() async throws {
        let preferences = try makePreferences()
        try await persistPreferencesImmediately(
            preferences,
            failure: .preferencePersistence,
        )
        await configureExperienceCoordinator(with: preferences.playlist)
    }

    func persistPreferencesImmediately(
        _ preferences: ThrowPreferences,
        failure: ThrowPostLaunchFailure,
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            enqueuePreferenceSave(
                .immediate(preferences, failure: failure, continuation),
            )
        }
    }

    /// Waits until no save or preference-backed mutation can enqueue more work.
    public func flushPreferencesSave() async {
        guard Task.isCancelled == false else { return }
        await withCheckedContinuation { continuation in
            preferencePersistence.waitForQuiescence(continuation)
            #if DEBUG
                preferenceFlushDidRegisterForTesting?()
            #endif
        }
    }

    func beginPreferenceMutation() -> ThrowPreferenceProducerLease? {
        preferencePersistence.beginMutation()
    }

    func finishPreferenceMutation(_ producer: ThrowPreferenceProducerLease) {
        let failures = preferencePersistence.finishMutation(producer)
        for failure in failures {
            schedulePreferencesSave(failure: failure)
        }
        preferencePersistence.finishProducer(producer)
    }

    func beginPreferenceProducer(
        _ kind: ThrowPreferenceProducerLease.Kind,
    ) -> ThrowPreferenceProducerLease? {
        preferencePersistence.beginProducer(kind)
    }

    func finishPreferenceProducer(_ producer: ThrowPreferenceProducerLease) {
        preferencePersistence.finishProducer(producer)
    }

    func waitForPreferenceSaveWorker() async {
        while let worker = preferencePersistence.worker {
            await worker.value
        }
    }

    /// Persists a mutation against the latest complete preference snapshot.
    /// An error after the first durable write becomes pending reconciliation.
    func persistReconciledPreferenceMutation<Publication, Preparation>(
        failure: ThrowPostLaunchFailure,
        makeMutation: (ThrowPreferenceSnapshot) throws
            -> ThrowPreferenceMutation<Publication>,
        prepareForPublication: () -> Preparation,
        publish: (Publication) -> Void,
    ) async -> ThrowPreferenceMutationOutcome<Preparation> {
        var commitState = ThrowPreferenceMutationCommitState<Publication>.uncommitted
        while true {
            let base = preferenceSnapshot
            let candidate: PersistableThrowPreferenceMutation<Publication>
            do {
                candidate = try persistablePreferenceMutation(
                    from: base,
                    makeMutation: makeMutation,
                )
            } catch {
                switch commitState {
                    case .uncommitted:
                        recordPostLaunchFailure(failure, error: error)
                        return .notCommitted
                    case let .committed(committedCandidate):
                        recordPostLaunchFailure(.preferencePersistence, error: error)
                        return publishCommittedPreferenceMutation(
                            committedCandidate,
                            targetFailure: failure,
                            prepareForPublication: prepareForPublication,
                            publish: publish,
                        )
                }
            }

            let attemptFailure: ThrowPostLaunchFailure = switch commitState {
                case .uncommitted: failure
                case .committed: .preferencePersistence
            }
            do {
                try Task.checkCancellation()
                try await persistPreferencesImmediately(
                    candidate.preferences,
                    failure: attemptFailure,
                )
            } catch {
                switch commitState {
                    case .uncommitted:
                        return .notCommitted
                    case let .committed(committedCandidate):
                        let publicationCandidate: PersistableThrowPreferenceMutation<Publication>
                        do {
                            publicationCandidate = try persistablePreferenceMutation(
                                from: preferenceSnapshot,
                                makeMutation: makeMutation,
                            )
                        } catch {
                            recordPostLaunchFailure(.preferencePersistence, error: error)
                            publicationCandidate = committedCandidate
                        }
                        return publishCommittedPreferenceMutation(
                            publicationCandidate,
                            targetFailure: failure,
                            prepareForPublication: prepareForPublication,
                            publish: publish,
                        )
                }
            }

            commitState = .committed(candidate)
            guard base == preferenceSnapshot else { continue }

            let preparation = prepareForPublication()
            publishPreferenceSnapshot(ThrowPreferenceSnapshot(candidate.preferences))
            publish(candidate.publication)
            resolveDeferredPreferenceFailuresAfterReconciledWrite()
            return .committed(preparation)
        }
    }

    private func persistablePreferenceMutation<Publication>(
        from base: ThrowPreferenceSnapshot,
        makeMutation: (ThrowPreferenceSnapshot) throws
            -> ThrowPreferenceMutation<Publication>,
    ) throws -> PersistableThrowPreferenceMutation<Publication> {
        let mutation = try makeMutation(base)
        let preferences = try makePreferences(
            setupState: mutation.snapshot.setupState,
            globalPreferences: mutation.snapshot.globalPreferences,
            airAndSpacePreferences: mutation.snapshot.airAndSpacePreferences,
            projectionPlaylist: mutation.snapshot.projectionPlaylist,
        )
        return PersistableThrowPreferenceMutation(
            preferences: preferences,
            publication: mutation.publication,
        )
    }

    private func publishCommittedPreferenceMutation<Publication, Preparation>(
        _ candidate: PersistableThrowPreferenceMutation<Publication>,
        targetFailure: ThrowPostLaunchFailure,
        prepareForPublication: () -> Preparation,
        publish: (Publication) -> Void,
    ) -> ThrowPreferenceMutationOutcome<Preparation> {
        preferencePersistence.recordDeferredFailure(.preferencePersistence)
        let preparation = prepareForPublication()
        publishPreferenceSnapshot(ThrowPreferenceSnapshot(candidate.preferences))
        publish(candidate.publication)
        resolvePostLaunchFailure(targetFailure.owner)
        return .committed(preparation)
    }

    var preferenceSnapshot: ThrowPreferenceSnapshot {
        ThrowPreferenceSnapshot(
            setupState: setupState,
            globalPreferences: globalPreferences,
            airAndSpacePreferences: airAndSpacePreferences,
            projectionPlaylist: projectionPlaylist,
        )
    }

    func resolveDeferredPreferenceFailuresAfterReconciledWrite() {
        let failures = preferencePersistence.takeDeferredFailures()
        for failure in failures {
            resolvePostLaunchFailure(failure.owner)
        }
    }

    private func publishPreferenceSnapshot(_ snapshot: ThrowPreferenceSnapshot) {
        setupState = snapshot.setupState
        globalPreferences = snapshot.globalPreferences
        airAndSpacePreferences = snapshot.airAndSpacePreferences
        projectionPlaylist = snapshot.projectionPlaylist
    }

    private func enqueuePreferenceSave(_ request: PreferenceSaveRequest) {
        preferencePersistence.enqueue(request) { [self] in
            Task(name: "Throw save preferences") {
                await drainPreferenceSaveQueue()
            }
        }
    }

    private func drainPreferenceSaveQueue() async {
        while let request = preferencePersistence.takeNextRequest() {
            do {
                try await preferenceStore.save(request.preferences)
                for failure in request.failures {
                    resolvePostLaunchFailure(failure.owner)
                }
                request.resume()
            } catch let error as CancellationError {
                request.resume(throwing: error)
            } catch {
                for failure in request.failures {
                    recordPostLaunchFailure(failure, error: error)
                }
                request.resume(throwing: error)
            }
        }
        preferencePersistence.workerDidFinish()
        preferencePersistence.resumeQuiescenceWaitersIfNeeded()
    }

    func makePreferences() throws -> ThrowPreferences {
        try makePreferences(setupState: setupState)
    }

    func makePreferences(
        setupState: ThrowSetupState,
    ) throws -> ThrowPreferences {
        try makePreferences(
            setupState: setupState,
            globalPreferences: globalPreferences,
            airAndSpacePreferences: airAndSpacePreferences,
        )
    }

    func makePreferences(
        setupState: ThrowSetupState,
        globalPreferences: ThrowGlobalPreferences,
        airAndSpacePreferences: AirAndSpacePreferences,
    ) throws -> ThrowPreferences {
        try makePreferences(
            setupState: setupState,
            globalPreferences: globalPreferences,
            airAndSpacePreferences: airAndSpacePreferences,
            projectionPlaylist: projectionPlaylist,
        )
    }

    func makePreferences(
        setupState: ThrowSetupState,
        globalPreferences: ThrowGlobalPreferences,
        airAndSpacePreferences: AirAndSpacePreferences,
        projectionPlaylist: ProjectionPlaylist,
    ) throws -> ThrowPreferences {
        let playlist: ProjectionPlaylist = if setupState.configuredExperienceIDs
            .contains(.airAndSpace),
            projectionPlaylist.entry(for: .airAndSpace) == nil
        {
            try ProjectionPlaylist(
                entries: [
                    ProjectionPlaylistEntry(
                        experienceID: .airAndSpace,
                        dwellDuration: .defaultValue,
                    ),
                ],
                automaticRotationEnabled: false,
                selectedExperienceID: .airAndSpace,
                configuredExperienceIDs: [.airAndSpace],
                catalog: .standard,
            )
        } else {
            projectionPlaylist
        }
        return try ThrowPreferences(
            setupState: setupState,
            global: globalPreferences,
            playlist: playlist,
            airAndSpace: airAndSpacePreferences,
        )
    }

    func updateQuietSchedule(_ schedule: QuietSchedule) {
        updateGlobalPreferences(globalPreferences.replacingQuietSchedule(schedule))
    }
}

/// All preference-backed session values captured in one comparable revision.
struct ThrowPreferenceSnapshot: Equatable {
    let setupState: ThrowSetupState
    let globalPreferences: ThrowGlobalPreferences
    let airAndSpacePreferences: AirAndSpacePreferences
    let projectionPlaylist: ProjectionPlaylist

    init(
        setupState: ThrowSetupState,
        globalPreferences: ThrowGlobalPreferences,
        airAndSpacePreferences: AirAndSpacePreferences,
        projectionPlaylist: ProjectionPlaylist,
    ) {
        self.setupState = setupState
        self.globalPreferences = globalPreferences
        self.airAndSpacePreferences = airAndSpacePreferences
        self.projectionPlaylist = projectionPlaylist
    }

    init(_ preferences: ThrowPreferences) {
        self.init(
            setupState: preferences.setupState,
            globalPreferences: preferences.global,
            airAndSpacePreferences: preferences.airAndSpace,
            projectionPlaylist: preferences.playlist,
        )
    }

    func replacingSetupState(_ setupState: ThrowSetupState) -> Self {
        Self(
            setupState: setupState,
            globalPreferences: globalPreferences,
            airAndSpacePreferences: airAndSpacePreferences,
            projectionPlaylist: projectionPlaylist,
        )
    }
}

/// A candidate snapshot and the non-persistent state published with it.
struct ThrowPreferenceMutation<Publication> {
    let snapshot: ThrowPreferenceSnapshot
    let publication: Publication
}

/// Proves whether a caller can roll back a preference-backed operation.
enum ThrowPreferenceMutationOutcome<Success> {
    case notCommitted
    case committed(Success)
}

private enum ThrowPreferenceMutationCommitState<Publication> {
    case uncommitted
    case committed(PersistableThrowPreferenceMutation<Publication>)
}

private struct PersistableThrowPreferenceMutation<Publication> {
    let preferences: ThrowPreferences
    let publication: Publication
}

/// Proves that an asynchronous preference producer began before admission closed.
struct ThrowPreferenceProducerLease: Hashable {
    enum Kind: Hashable {
        case mutation
        case experienceSelection
        case experienceTransition
    }

    fileprivate struct ID: Hashable {
        static let initial = ID(rawValue: 0)

        let rawValue: UInt64

        func successor() -> ID {
            precondition(rawValue < UInt64.max, "A preference producer ID must not overflow")
            return ID(rawValue: rawValue + 1)
        }
    }

    let kind: Kind
    fileprivate let id: ID
}

/// The complete save and mutation lifecycle for session preferences.
@MainActor
struct ThrowPreferencePersistenceState {
    private enum Activity {
        case idle
        case saving(
            worker: Task<Void, Never>,
            pending: [PreferenceSaveRequest],
        )
        case mutating(deferredFailures: ThrowPostLaunchFailureLedger)
        case mutatingAndSaving(
            worker: Task<Void, Never>,
            pending: [PreferenceSaveRequest],
            deferredFailures: ThrowPostLaunchFailureLedger,
        )
    }

    private enum ProducerAdmission {
        case open(
            nextID: ThrowPreferenceProducerLease.ID,
            active: Set<ThrowPreferenceProducerLease>,
        )
        case closed(
            nextID: ThrowPreferenceProducerLease.ID,
            active: Set<ThrowPreferenceProducerLease>,
        )

        var active: Set<ThrowPreferenceProducerLease> {
            switch self {
                case let .open(_, active), let .closed(_, active):
                    active
            }
        }
    }

    private var activity = Activity.idle
    private var producerAdmission: ProducerAdmission
    private var quiescenceWaiters: [CheckedContinuation<Void, Never>] = []

    init(acceptsProducers: Bool) {
        producerAdmission = if acceptsProducers {
            .open(nextID: .initial, active: [])
        } else {
            .closed(nextID: .initial, active: [])
        }
    }

    var isMutationActive: Bool {
        switch activity {
            case .mutating, .mutatingAndSaving:
                true
            case .idle, .saving:
                false
        }
    }

    var worker: Task<Void, Never>? {
        switch activity {
            case let .saving(worker, _), let .mutatingAndSaving(worker, _, _):
                worker
            case .idle, .mutating:
                nil
        }
    }

    var lastRequestIsCoalescible: Bool {
        switch activity {
            case let .saving(_, pending), let .mutatingAndSaving(_, pending, _):
                pending.last?.isCoalescible == true
            case .idle, .mutating:
                false
        }
    }

    #if DEBUG
        var hasPendingImmediateRequest: Bool {
            switch activity {
                case let .saving(_, pending), let .mutatingAndSaving(_, pending, _):
                    pending.contains(where: \.isImmediate)
                case .idle, .mutating:
                    false
            }
        }

        var quiescenceWaiterCount: Int {
            quiescenceWaiters.count
        }

        var activeProducerCount: Int {
            producerAdmission.active.count
        }
    #endif

    mutating func setAcceptsProducers(_ acceptsProducers: Bool) {
        switch (producerAdmission, acceptsProducers) {
            case (.open, true), (.closed, false):
                return
            case let (.open(nextID, active), false):
                producerAdmission = .closed(nextID: nextID, active: active)
            case let (.closed(nextID, active), true):
                producerAdmission = .open(nextID: nextID, active: active)
        }
    }

    mutating func beginProducer(
        _ kind: ThrowPreferenceProducerLease.Kind,
    ) -> ThrowPreferenceProducerLease? {
        switch producerAdmission {
            case let .open(nextID, active):
                let producer = ThrowPreferenceProducerLease(kind: kind, id: nextID)
                producerAdmission = .open(
                    nextID: nextID.successor(),
                    active: active.union([producer]),
                )
                return producer
            case .closed:
                return nil
        }
    }

    mutating func finishProducer(_ producer: ThrowPreferenceProducerLease) {
        switch producerAdmission {
            case let .open(nextID, active):
                producerAdmission = .open(
                    nextID: nextID,
                    active: removing(producer, from: active),
                )
            case let .closed(nextID, active):
                producerAdmission = .closed(
                    nextID: nextID,
                    active: removing(producer, from: active),
                )
        }
        resumeQuiescenceWaitersIfNeeded()
    }

    mutating func beginMutation() -> ThrowPreferenceProducerLease? {
        guard isMutationActive == false,
              let producer = beginProducer(.mutation)
        else { return nil }
        switch activity {
            case .idle:
                activity = .mutating(deferredFailures: ThrowPostLaunchFailureLedger())
            case let .saving(worker, pending):
                activity = .mutatingAndSaving(
                    worker: worker,
                    pending: pending,
                    deferredFailures: ThrowPostLaunchFailureLedger(),
                )
            case .mutating, .mutatingAndSaving:
                preconditionFailure("A preference mutation cannot overlap another mutation")
        }
        return producer
    }

    mutating func finishMutation(
        _ producer: ThrowPreferenceProducerLease,
    ) -> [ThrowPostLaunchFailure] {
        precondition(
            producer.kind == .mutation && producerAdmission.active.contains(producer),
            "Only the active preference mutation producer can finish the mutation",
        )
        switch activity {
            case let .mutating(deferredFailures):
                activity = .idle
                return deferredFailures.failures
            case let .mutatingAndSaving(worker, pending, deferredFailures):
                activity = .saving(worker: worker, pending: pending)
                return deferredFailures.failures
            case .idle, .saving:
                preconditionFailure("A preference mutation must be active before it finishes")
        }
    }

    mutating func recordDeferredFailure(_ failure: ThrowPostLaunchFailure) {
        switch activity {
            case let .mutating(deferredFailures):
                activity = .mutating(
                    deferredFailures: deferredFailures.recording(failure),
                )
            case let .mutatingAndSaving(worker, pending, deferredFailures):
                activity = .mutatingAndSaving(
                    worker: worker,
                    pending: pending,
                    deferredFailures: deferredFailures.recording(failure),
                )
            case .idle, .saving:
                preconditionFailure("Only a preference mutation can defer a save")
        }
    }

    mutating func takeDeferredFailures() -> [ThrowPostLaunchFailure] {
        switch activity {
            case let .mutating(deferredFailures):
                activity = .mutating(deferredFailures: ThrowPostLaunchFailureLedger())
                return deferredFailures.failures
            case let .mutatingAndSaving(worker, pending, deferredFailures):
                activity = .mutatingAndSaving(
                    worker: worker,
                    pending: pending,
                    deferredFailures: ThrowPostLaunchFailureLedger(),
                )
                return deferredFailures.failures
            case .idle, .saving:
                preconditionFailure("Only a preference mutation has deferred failures")
        }
    }

    mutating func enqueue(
        _ request: PreferenceSaveRequest,
        makeWorker: () -> Task<Void, Never>,
    ) {
        switch activity {
            case .idle:
                activity = .saving(worker: makeWorker(), pending: [request])
            case let .saving(worker, pending):
                activity = .saving(worker: worker, pending: pending + [request])
            case let .mutating(deferredFailures):
                activity = .mutatingAndSaving(
                    worker: makeWorker(),
                    pending: [request],
                    deferredFailures: deferredFailures,
                )
            case let .mutatingAndSaving(worker, pending, deferredFailures):
                activity = .mutatingAndSaving(
                    worker: worker,
                    pending: pending + [request],
                    deferredFailures: deferredFailures,
                )
        }
    }

    mutating func coalesceLastRequest(
        with preferences: ThrowPreferences,
        failure: ThrowPostLaunchFailure,
    ) {
        switch activity {
            case let .saving(worker, pending):
                activity = .saving(
                    worker: worker,
                    pending: coalescingLastRequest(
                        in: pending,
                        with: preferences,
                        failure: failure,
                    ),
                )
            case let .mutatingAndSaving(worker, pending, deferredFailures):
                activity = .mutatingAndSaving(
                    worker: worker,
                    pending: coalescingLastRequest(
                        in: pending,
                        with: preferences,
                        failure: failure,
                    ),
                    deferredFailures: deferredFailures,
                )
            case .idle, .mutating:
                preconditionFailure("A coalesced save requires a pending request")
        }
    }

    mutating func takeNextRequest() -> PreferenceSaveRequest? {
        switch activity {
            case let .saving(worker, pending):
                guard let request = pending.first else { return nil }
                activity = .saving(worker: worker, pending: Array(pending.dropFirst()))
                return request
            case let .mutatingAndSaving(worker, pending, deferredFailures):
                guard let request = pending.first else { return nil }
                activity = .mutatingAndSaving(
                    worker: worker,
                    pending: Array(pending.dropFirst()),
                    deferredFailures: deferredFailures,
                )
                return request
            case .idle, .mutating:
                return nil
        }
    }

    mutating func workerDidFinish() {
        switch activity {
            case let .saving(_, pending):
                precondition(pending.isEmpty, "A preference worker must drain its queue")
                activity = .idle
            case let .mutatingAndSaving(_, pending, deferredFailures):
                precondition(pending.isEmpty, "A preference worker must drain its queue")
                activity = .mutating(deferredFailures: deferredFailures)
            case .idle, .mutating:
                preconditionFailure("A preference worker must be active before it finishes")
        }
    }

    mutating func waitForQuiescence(_ continuation: CheckedContinuation<Void, Never>) {
        guard isQuiescent else {
            quiescenceWaiters.append(continuation)
            return
        }
        continuation.resume()
    }

    mutating func resumeQuiescenceWaitersIfNeeded() {
        guard isQuiescent else { return }
        let waiters = quiescenceWaiters
        quiescenceWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private var isQuiescent: Bool {
        guard case .idle = activity else { return false }
        return producerAdmission.active.isEmpty
    }

    private func removing(
        _ producer: ThrowPreferenceProducerLease,
        from active: Set<ThrowPreferenceProducerLease>,
    ) -> Set<ThrowPreferenceProducerLease> {
        var active = active
        precondition(
            active.remove(producer) != nil,
            "A preference producer must finish exactly once",
        )
        return active
    }

    private func coalescingLastRequest(
        in pending: [PreferenceSaveRequest],
        with preferences: ThrowPreferences,
        failure: ThrowPostLaunchFailure,
    ) -> [PreferenceSaveRequest] {
        guard let last = pending.last, last.isCoalescible else {
            preconditionFailure("The final preference request must be coalescible")
        }
        var result = pending
        result[result.index(before: result.endIndex)] = last.coalescing(
            preferences,
            failure: failure,
        )
        return result
    }
}

enum PreferenceSaveRequest {
    case coalesced(
        ThrowPreferences,
        failureLedger: ThrowPostLaunchFailureLedger,
    )
    case immediate(
        ThrowPreferences,
        failure: ThrowPostLaunchFailure,
        CheckedContinuation<Void, any Error>,
    )

    var preferences: ThrowPreferences {
        switch self {
            case let .coalesced(preferences, _), let .immediate(preferences, _, _):
                preferences
        }
    }

    var failures: [ThrowPostLaunchFailure] {
        switch self {
            case let .coalesced(_, failureLedger):
                failureLedger.failures
            case let .immediate(_, failure, _):
                [failure]
        }
    }

    func coalescing(
        _ preferences: ThrowPreferences,
        failure: ThrowPostLaunchFailure,
    ) -> Self {
        guard case let .coalesced(_, failureLedger) = self else { return self }
        return .coalesced(
            preferences,
            failureLedger: failureLedger.recording(failure),
        )
    }

    var isCoalescible: Bool {
        if case .coalesced = self { true } else { false }
    }

    var isImmediate: Bool {
        if case .immediate = self { true } else { false }
    }

    func resume() {
        if case let .immediate(_, _, continuation) = self {
            continuation.resume()
        }
    }

    func resume(throwing error: any Error) {
        if case let .immediate(_, _, continuation) = self {
            continuation.resume(throwing: error)
        }
    }
}

extension ThrowSetupState {
    func updatingSourceSelection(_ sourceSelection: AircraftSourceSelection) -> Self {
        switch self {
            case let .onboarding(setup):
                return .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: sourceSelection,
                        location: setup.location,
                        projection: setup.projection,
                    ),
                )
            case let .configured(setup):
                if case let .configured(source) = sourceSelection,
                   source == setup.source
                {
                    return self
                }
                return .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: sourceSelection,
                        location: .confirmed(
                            mode: setup.locationMode,
                            location: setup.confirmedLocation,
                        ),
                        projection: .selected(setup.projectionMode),
                    ),
                )
        }
    }

    func selectingSource(_ source: AircraftSourceConfiguration?) -> Self {
        if source == selectedSource { return self }
        let sourceSelection = source.map(AircraftSourceSelection.awaitingValidation)
            ?? .unconfigured
        return updatingSourceSelection(sourceSelection)
    }

    func validatingSource(_ source: AircraftSourceConfiguration?) -> Self {
        guard let source else {
            let sourceSelection = selectedSource.map(AircraftSourceSelection.awaitingValidation)
                ?? .unconfigured
            return updatingSourceSelection(sourceSelection)
        }
        guard selectedSource == source else { return self }
        return updatingSourceSelection(.configured(source))
    }

    func replacingSource(_ source: AircraftSourceConfiguration) -> Self {
        switch self {
            case let .onboarding(setup):
                .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: .configured(source),
                        location: setup.location,
                        projection: setup.projection,
                    ),
                )
            case let .configured(setup):
                .configured(
                    ThrowConfiguredSetup(
                        source: source,
                        locationMode: setup.locationMode,
                        confirmedLocation: setup.confirmedLocation,
                        projectionMode: setup.projectionMode,
                    ),
                )
        }
    }

    func updatingLocation(
        mode: ObserverLocationMode,
        confirmedLocation: ConfirmedObserverLocation?,
    ) -> Self {
        let locationState: ObserverLocationSetupState = if let confirmedLocation {
            .confirmed(mode: mode, location: confirmedLocation)
        } else {
            .unconfirmed(mode: mode)
        }
        switch self {
            case let .onboarding(setup):
                return .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: setup.sourceSelection,
                        location: locationState,
                        projection: setup.projection,
                    ),
                )
            case let .configured(setup):
                guard let confirmedLocation else {
                    return .onboarding(
                        ThrowOnboardingSetup(
                            sourceSelection: .configured(setup.source),
                            location: locationState,
                            projection: .selected(setup.projectionMode),
                        ),
                    )
                }
                return .configured(
                    ThrowConfiguredSetup(
                        source: setup.source,
                        locationMode: mode,
                        confirmedLocation: confirmedLocation,
                        projectionMode: setup.projectionMode,
                    ),
                )
        }
    }

    func updatingProjectionMode(_ projectionMode: ProjectionMode) -> Self {
        switch self {
            case let .onboarding(setup):
                .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: setup.sourceSelection,
                        location: setup.location,
                        projection: .selected(projectionMode),
                    ),
                )
            case let .configured(setup):
                .configured(
                    ThrowConfiguredSetup(
                        source: setup.source,
                        locationMode: setup.locationMode,
                        confirmedLocation: setup.confirmedLocation,
                        projectionMode: projectionMode,
                    ),
                )
        }
    }

    func completing(projectionMode: ProjectionMode) -> Self? {
        guard case let .onboarding(setup) = self,
              case let .configured(source) = setup.sourceSelection,
              case let .confirmed(locationMode, confirmedLocation) = setup.location
        else { return nil }
        return .configured(
            ThrowConfiguredSetup(
                source: source,
                locationMode: locationMode,
                confirmedLocation: confirmedLocation,
                projectionMode: projectionMode,
            ),
        )
    }
}
