import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

struct PeriscopeAuthoringRulesTests {
    @Test
    func `macro-authored scope and event pass`() throws {
        let report = try evaluate(
            """
            @LogScope("Worker")
            enum WorkerLog {
                @LogEvent("finished", message: "Finished")
                struct Finished {
                    @LogField("count", exposure: .shareable, kind: .count)
                    var count: Int
                }
            }
            """,
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func `event nested in a scope requires LogEvent`() throws {
        let report = try evaluate(
            """
            @LogScope("Worker")
            enum WorkerLog {
                struct Finished {}
            }
            """,
        )

        #expect(report.violations.map(\.rule.id) == ["periscope.structured_events_use_macro"])
    }

    @Test
    func `event namespace requires LogScope`() throws {
        let report = try evaluate(
            """
            enum WorkerLog {
                @LogEvent("finished", message: "Finished")
                struct Finished {}
            }
            """,
        )

        #expect(report.violations.map(\.rule.id) == ["periscope.event_namespaces_use_macro"])
    }

    @Test(arguments: ["LogEvent", "LogScopeDefinition"])
    func `manual logging conformances fail`(_ protocolName: String) throws {
        let report = try evaluate("struct Manual: \(protocolName) {}")

        let expected = protocolName == "LogEvent"
            ? "periscope.manual_event_conformance"
            : "periscope.manual_scope_conformance"
        #expect(report.violations.count == 1)
        #expect(report.violations.first?.rule.id.rawValue == expected)
    }

    @Test(arguments: [
        "remoteMessage",
        "remoteFields",
        "RemoteLogField",
        "RemoteLogFieldKey",
        "RemoteLogFieldValue",
        "RemoteLogCategory",
    ])
    func `legacy remote APIs fail`(_ name: String) throws {
        let report = try evaluate("let value = \(name)")

        #expect(report.violations.map(\.rule.id) == ["periscope.legacy_remote_api"])
    }

    @Test
    func `LogField outside an event fails`() throws {
        let report = try evaluate(
            """
            struct Payload {
                @LogField("count", exposure: .shareable, kind: .count)
                var count: Int
            }
            """,
        )

        #expect(report.violations.map(\.rule.id) == ["periscope.log_field_placement"])
    }

    private func evaluate(_ source: String) throws -> RuleReport {
        try RuleTestHarness(periscopeAuthoringRules).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Shared/Periscope/Fixture.swift",
                    component: "periscope",
                    source: source,
                )
            },
        )
    }
}
