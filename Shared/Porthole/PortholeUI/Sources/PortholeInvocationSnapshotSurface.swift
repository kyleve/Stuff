#if DEBUG && canImport(UIKit)
    import Foundation
    import PortholeRuntime
    import SwiftUI

    /// Uses the normal invocation model and wire client; its executor retains one fixed sample.
    struct PortholeInvocationSnapshotSurface: View {
        let stopFails: Bool
        @State private var fixture: Result<PortholeInvocationSnapshotFixture, any Error>?

        var body: some View {
            NavigationStack {
                switch fixture {
                    case nil: ProgressView("Preparing synthetic watch…")
                    case let .success(fixture):
                        PortholeInvocationView(
                            model: fixture.model,
                            execute: fixture.executor.invoke,
                            presentation: nil,
                        )
                    case let .failure(error): Text(
                            "Snapshot setup failed: \(error.localizedDescription)",
                        )
                }
            }
            .portholeBroadwayRoot()
            .task {
                guard fixture == nil else { return }
                let prepared = PortholeInvocationSnapshotFixture(stopFails: stopFails)
                do {
                    try await prepared.prepare()
                    try Task.checkCancellation()
                    fixture = .success(prepared)
                } catch is CancellationError {
                    prepared.model.cancel()
                } catch {
                    prepared.model.cancel()
                    fixture = .failure(error)
                }
            }
            .onDisappear {
                if case let .success(fixture) = fixture { fixture.model.cancel() }
            }
        }
    }

    @MainActor
    private struct PortholeInvocationSnapshotFixture {
        let model: PortholeInvocationModel
        let executor: PortholeInvocationSnapshotExecutor
        let stopFails: Bool

        init(stopFails: Bool) {
            self.stopFails = stopFails
            let capability = PortholeCapability(
                id: .init(rawValue: "example.detector.inputs"),
                module: .init(rawValue: "Example"),
                name: "Detector inputs",
                summary: "Inspect the inputs for the selected day.",
                parameters: [.init(
                    name: "day",
                    summary: "Selected calendar day",
                    schema: .string,
                    required: true,
                )],
                result: .any,
                effect: .read,
                source: nil,
                ownership: .adapter,
                availability: .callable,
            )
            model = PortholeInvocationModel(
                capability: capability,
                objects: [],
                scope: .init(
                    id: .init(rawValue: "synthetic-detector"),
                    generation: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
                ),
            )
            model.fields.first?.text = "2026-09-13"
            executor = PortholeInvocationSnapshotExecutor(
                capability: capability,
                stopFails: stopFails,
            )
        }

        func prepare() async throws {
            model.watch(execute: executor.invoke)
            try await waitUntil {
                if case let .watching(session) = model.observation.state { session.sample != nil }
                else { false }
            }
            if stopFails {
                model.observation.stop()
                try await waitUntil {
                    if case .stopFailed = model.observation.state { true }
                    else { false }
                }
            }
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !predicate() {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw PortholeError
                        .operationFailed("The synthetic watch did not reach its expected state.")
                }
                await Task.yield()
            }
        }
    }

    /// A stopped or cancelled read always releases its continuation; it creates no polling timer.
    private actor PortholeInvocationSnapshotExecutor: PortholeExecuting {
        let capability: PortholeCapability
        let stopFails: Bool
        private var pendingRead: CheckedContinuation<PortholeValue, any Error>?

        init(capability: PortholeCapability, stopFails: Bool) {
            self.capability = capability
            self.stopFails = stopFails
        }

        func capabilities(in _: PortholeScopeToken) -> [PortholeCapability] {
            [capability]
        }

        func invoke(_ invocation: PortholeInvocation) async throws -> PortholeValue {
            switch invocation.capabilityID {
                case PortholeObservationCapabilities.start:
                    guard let value = invocation.arguments["request"] else {
                        throw PortholeError
                            .invalidArguments("Missing synthetic observation request.")
                    }
                    let request = try value.decode(PortholeObservationRequest.self)
                    return try .encoding(request.reference)
                case PortholeObservationCapabilities.read:
                    guard let value = invocation.arguments["observation"] else {
                        throw PortholeError
                            .invalidArguments("Missing synthetic observation reference.")
                    }
                    let reference = try value.decode(PortholeObservationReference.self)
                    if invocation.arguments["afterSequence"] == .null {
                        return try .encoding(PortholeObservationSnapshot(
                            observation: reference,
                            state: .sample(.init(
                                sequence: 4,
                                invocationID: UUID(
                                    uuidString: "33333333-4444-5555-6666-777777777777",
                                )!,
                                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                value: .object([
                                    "sampleCount": .integer(18),
                                    "candidateFlight": .bool(false),
                                ]),
                            )),
                        ))
                    }
                    return try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { continuation in
                            if Task
                                .isCancelled { continuation.resume(throwing: CancellationError()) }
                            else { pendingRead = continuation }
                        }
                    } onCancel: {
                        Task { await self.cancelRead() }
                    }
                case PortholeObservationCapabilities.stop:
                    cancelRead()
                    if stopFails {
                        throw PortholeError.operationFailed("The paired device is offline.")
                    }
                    return .null
                default:
                    throw PortholeError
                        .unsupported("This snapshot only supports its synthetic watch.")
            }
        }

        private func cancelRead() {
            let read = pendingRead
            pendingRead = nil
            read?.resume(throwing: CancellationError())
        }
    }
#endif
