import Foundation
import PeriscopeCore
import Testing

private final class FreeformController: LogContextProviding {
    let system: Periscope

    var logSystem: Periscope {
        system
    }

    init(system: Periscope) {
        self.system = system
    }
}

private final class TypedController: LogContextProviding {
    typealias LogEventType = PhotoLogs

    let system: Periscope

    var logSystem: Periscope {
        system
    }

    init(system: Periscope) {
        self.system = system
    }
}

struct LogContextProvidingTests {
    let sink = CapturingSink()
    let system: Periscope

    init() {
        system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
    }

    @Test func logScopesToTheTypeAndInstance() throws {
        let controller = FreeformController(system: system)
        let scope = controller.log.primaryScope

        #expect(scope.name == "#1")
        let parentID = try #require(scope.parentID)
        let parent = try #require(system.scope(for: parentID))
        #expect(parent.name == "FreeformController")
        #expect(parent.parentID == nil)
    }

    @Test func sameInstanceKeepsItsScope() {
        let controller = FreeformController(system: system)
        #expect(controller.log.primaryScope == controller.log.primaryScope)
    }

    @Test func distinctInstancesGetDistinctNumberedScopes() {
        let first = FreeformController(system: system)
        let second = FreeformController(system: system)

        #expect(first.log.primaryScope.name == "#1")
        #expect(second.log.primaryScope.name == "#2")
        #expect(first.log.primaryScope != second.log.primaryScope)
        #expect(first.log.primaryScope.parentID == second.log.primaryScope.parentID)
    }

    @Test func instanceCountersAreIndependentPerType() {
        _ = FreeformController(system: system).log
        let typed = TypedController(system: system)
        #expect(typed.log.primaryScope.name == "#1")
    }

    @Test func typedConformersGetATypedLogger() async {
        let controller = TypedController(system: system)

        controller.log { PhotoLogs(photoID: "p1") }
        await system.flush()

        #expect(sink.records.map(\.message) == ["photo p1"])
        #expect(sink.records.first?.scopes == [controller.log.primaryScope.id])
    }

    @Test func freeformLoggingWorksOnAnyConformer() async {
        let controller = FreeformController(system: system)

        controller.log.warning("degraded")
        await system.flush()

        #expect(sink.records.map(\.message) == ["degraded"])
        #expect(sink.records.first?.level == .warning)
    }

    @Test func bothScopesAreDefinedInTheSystem() {
        let controller = FreeformController(system: system)
        let instance = controller.log.primaryScope

        #expect(system.scope(for: instance.id) == instance)
        let parentID = instance.parentID
        #expect(parentID.flatMap { system.scope(for: $0) } != nil)
    }
}
