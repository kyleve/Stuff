import PeriscopeCore
import PeriscopeUI
import SwiftUI
import Testing
import UIKit
import WhereTesting

/// Reads the accumulated context from the environment and logs once on
/// appear, exercising exactly what production views do.
private struct FreeformProbe: View {
    @Environment(\.logContext) private var log

    var body: some View {
        Color.clear.onAppear {
            log.info("probe")
        }
    }
}

/// Derives a typed logger from the environment context before emitting.
private struct TypedProbe: View {
    @Environment(\.logContext) private var log

    var body: some View {
        Color.clear.onAppear {
            log(PhotoLogs.self) { PhotoLogs(photoID: "p1") }
        }
    }
}

private final class PhotoModel: LogContextProviding {
    let system: Periscope

    var logSystem: Periscope {
        system
    }

    init(system: Periscope) {
        self.system = system
    }
}

@MainActor
struct LogContextEnvironmentTests {
    private func showAndAwaitRecords(
        _ view: some View,
        system: Periscope,
    ) throws -> [LogRecord] {
        let host = UIHostingController(rootView: AnyView(view))
        var records: [LogRecord] = []
        try show(host) { _ in
            try waitFor { !system.recentRecords().isEmpty }
            records = system.recentRecords()
        }
        return records
    }

    @Test func contextOutsideAnyModifierFallsBackToASharedRoot() {
        let log = EnvironmentValues().logContext
        #expect(log.primaryScope.name == Message.eventName)
        #expect(log.primaryScope.parentID == nil)
    }

    @Test func modifierGivesDescendantsTheContext() throws {
        let system = makeSystem()
        let screen = Log<AppLogs>(system: system)(for: "detail-screen")

        let records = try showAndAwaitRecords(
            FreeformProbe().logContext(screen),
            system: system,
        )

        #expect(records.first?.message == "probe")
        #expect(records.first?.scopes == screen.scopes.map(\.id))
    }

    @Test func stackedModifiersLinkWithTheNearestPrimary() throws {
        let system = makeSystem()
        let model = Log<PhotoLogs>(system: system)(for: "photo-9")
        let screen = Log<AppLogs>(system: system)(for: "detail-screen")

        let records = try showAndAwaitRecords(
            FreeformProbe()
                .logContext(model)
                .logContext(screen),
            system: system,
        )

        let expected = (model.scopes + screen.scopes).map(\.id)
        #expect(records.first?.scopes == expected)
    }

    @Test func tagsFlowThroughTheEnvironment() throws {
        let system = makeSystem()
        let key = LogTagKey("payment-id")
        let screen = Log<AppLogs>(system: system).tagged(key, "pay_123")

        let records = try showAndAwaitRecords(
            FreeformProbe().logContext(screen),
            system: system,
        )

        #expect(records.first?.tags == [key: "pay_123"])
    }

    @Test func typedLoggersDeriveFromTheEnvironmentContext() throws {
        let system = makeSystem()
        let screen = Log<AppLogs>(system: system)(for: "detail-screen")

        let records = try showAndAwaitRecords(
            TypedProbe().logContext(screen),
            system: system,
        )

        #expect(records.first?.message == "photo p1")
        let primary = try #require(records.first?.scopes.first)
        #expect(system.scope(for: primary)?.parentID == screen.primaryScope.id)
    }

    @Test func contextProvidersContributeTheirInstanceScope() throws {
        let system = makeSystem()
        let model = PhotoModel(system: system)

        let records = try showAndAwaitRecords(
            FreeformProbe().logContext(model),
            system: system,
        )

        #expect(records.first?.scopes == model.log.scopes.map(\.id))
    }
}
