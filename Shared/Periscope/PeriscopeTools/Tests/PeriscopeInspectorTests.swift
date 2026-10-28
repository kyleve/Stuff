import Foundation
@_spi(Testing) import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
struct PeriscopeInspectorTests {
    @Test func initMirrorsTheSystemFlag() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        system.isInspectModeEnabled = true

        let inspector = PeriscopeInspector(system: system, store: store)
        #expect(inspector.isEnabled)
    }

    @Test func togglingWritesThroughToTheSystem() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        let inspector = PeriscopeInspector(system: system, store: store)

        inspector.isEnabled = true
        #expect(system.isInspectModeEnabled)

        inspector.isEnabled = false
        #expect(!system.isInspectModeEnabled)
    }

    @Test func directSystemWritesFlowBackIntoTheInspector() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        let inspector = PeriscopeInspector(system: system, store: store)
        #expect(!inspector.isEnabled)

        system.isInspectModeEnabled = true
        let mirroredOn = await waitUntil { inspector.isEnabled }
        #expect(mirroredOn)

        system.isInspectModeEnabled = false
        let mirroredOff = await waitUntil { !inspector.isEnabled }
        #expect(mirroredOff)
    }

    @Test func mixedWritersConvergeWithoutPingPong() async throws {
        let store = try await PeriscopeStore.inMemory(session: makeSession())
        let system = Periscope(configuration: Periscope.Configuration(), sinks: [])
        let inspector = PeriscopeInspector(system: system, store: store)

        inspector.isEnabled = true
        system.isInspectModeEnabled = false
        inspector.isEnabled = true
        system.isInspectModeEnabled = false

        let converged = await waitUntil {
            !inspector.isEnabled && !system.isInspectModeEnabled
        }
        #expect(converged)
    }
}
