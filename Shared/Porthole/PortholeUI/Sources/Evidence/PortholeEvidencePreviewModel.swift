import Foundation
import Observation
import PortholeRuntime

/// Prepares the actual evidence model once before measurement and accessibility capture.
@MainActor @Observable
final class PortholeEvidencePreviewModel {
    enum Surface { case links, object, expired, relationships }
    struct Fixture {
        let controller: PortholePresentationController
        let object: PortholeObjectReference
        let value: PortholeValue
        let capability: PortholeCapability
        let context: PortholeContext
        let related: PortholeContext
        let evidence: PortholeEvidenceModel
    }

    let surface: Surface
    private(set) var fixture: Result<Fixture, any Error>?
    private var preparation: Task<Void, Never>?

    init(surface: Surface) {
        self.surface = surface
    }

    func prepare() async {
        if let preparation { await preparation.value; return }
        let preparation = Task { [self] in
            do { fixture = try await .success(makeFixture()) }
            catch {
                PortholeUILog.failures.error(
                    "Evidence preview failed: \(String(describing: error), privacy: .private)",
                )
                fixture = .failure(error)
            }
        }
        self.preparation = preparation
        await preparation.value
    }

    private func makeFixture() async throws -> Fixture {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "flight-investigation"))
        await registry.setEnabled(true)
        let object = try await registry.retain(PortholeEvidencePreviewActor(), in: scope)
        let source = PortholeSourceFile(
            path: "Example/FlightDetector.swift",
            content: "func identifyFlight() -> Bool {\n    false\n}",
        )
        try await registry.installSourceArchive(
            String(decoding: JSONEncoder().encode([source]), as: UTF8.self),
            in: scope,
        )
        let context = PortholeContext(
            id: .init(rawValue: "flight-issue"),
            title: "Why was this not a flight?",
            scope: scope,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            values: .object(["identifiedFlight": .bool(false)]),
            objects: [object],
            links: [.init(
                id: .init(rawValue: "flight-decision"),
                label: "Flight decision",
                relation: "explained by",
            )],
            source: .init(path: source.path, line: 2),
        )
        try await registry.capture(context)
        let related = PortholeContext(
            id: .init(rawValue: "flight-decision"),
            title: "Flight decision",
            scope: scope,
            capturedAt: context.capturedAt,
            values: .object(["endpointAirportsEqual": .bool(true)]),
            objects: [],
            links: [.init(
                id: context.id,
                label: context.title,
                relation: "rejected candidate produced",
            )],
            source: context.source,
        )
        try await registry.capture(related)
        let capability = PortholeCapability(
            id: .init(rawValue: "preview.flight.read"),
            module: .init(rawValue: "PortholeUI"),
            name: "PortholeEvidencePreviewActor.recordedDecision",
            summary: "Read the recorded flight decision.",
            parameters: [],
            result: .boolean,
            effect: .read,
            source: context.source,
            ownership: .actorInstance(typeName: "PortholeEvidencePreviewActor"),
            availability: .inspectable,
        )
        try await registry.describe(capability, in: scope)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Example",
        )
        controller.present(origin: .screen(context))
        await controller.refresh()
        let value = try PortholeValue.object([
            "receiver": .object(["$reference": .encoding(object)]),
            "context": .encoding(context),
            "source": .object([
                "path": .string(source.path),
                "line": .integer(2),
                "sha256": .string(source.sha256),
                "scope": .encoding(scope),
            ]),
        ])
        if case .expired = surface { await registry.invalidate(scope) }
        let evidence = PortholeEvidenceModel(reference: .object(object), registry: registry)
        await evidence.loadIfNeeded()
        return Fixture(
            controller: controller,
            object: object,
            value: value,
            capability: capability,
            context: context,
            related: related,
            evidence: evidence,
        )
    }
}

actor PortholeEvidencePreviewActor {}
