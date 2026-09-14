import Foundation
import Observation
import PortholeRuntime

/// One in-memory fixture survives measurement and accessibility rehosting.
@MainActor @Observable
final class PortholePreviewModel {
    enum State { case preparing, ready(PortholePresentationController), failed(String) }
    private(set) var state: State = .preparing
    private var preparation: Task<Void, Never>?

    func prepare() async {
        if let preparation { await preparation.value; return }
        let preparation = Task { [self] in
            do { state = try await .ready(makeController()) }
            catch {
                PortholeUILog.failures.error(
                    "Preview setup failed: \(String(describing: error), privacy: .private)",
                )
                state = .failed(String(describing: error))
            }
        }
        self.preparation = preparation
        await preparation.value
    }

    private func makeController() async throws -> PortholePresentationController {
        let controller = PortholePresentationController(
            registry: PortholeRegistry(journal: .init(url: nil), objectLimit: 20),
            applicationTitle: "Example app",
        )
        let registry = controller.registry
        let scope = await registry.createScope(id: .init(rawValue: "example-journey"))
        await registry.setEnabled(true)
        let source = PortholeSourceFile(
            path: "Example/FlightDetector.swift",
            content: "func identifyFlight() -> Bool {\n    false\n}",
        )
        let archive = try String(decoding: JSONEncoder().encode([source]), as: UTF8.self)
        try await registry.installSourceArchive(archive, in: scope)
        let context = PortholeContext(
            id: .init(rawValue: "example-issue"),
            title: "Border drift issue",
            scope: scope,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            values: .object([
                "detector": .string("Border drift"),
                "identifiedFlight": .bool(false),
            ]),
            objects: [],
            links: [],
            source: .init(path: source.path, line: 1),
        )
        try await registry.capture(context)
        try await registry.describe(
            PortholeCapability(
                id: .init(rawValue: "example.flight.evaluate"),
                module: .init(rawValue: "Example"),
                name: "FlightDetector.evaluate",
                summary: "Evaluate recorded flight evidence.",
                parameters: [.init(
                    name: "distance",
                    summary: "Distance in metres",
                    schema: .number,
                    required: true,
                )],
                result: .boolean,
                effect: .unknown,
                source: .init(
                    path: source.path,
                    line: 1,
                ),
                ownership: .adapter,
                availability: .unsupported("This fixture has no live detector."),
            ),
            in: scope,
        )
        controller.present(origin: .screen(context))
        await controller.refreshIfNeeded()
        return controller
    }
}
