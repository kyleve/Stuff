import Foundation
import PortholeCore
@testable import PortholeMCP
import Testing

struct MCPToolBuilderTests {
    @Test func sanitizesToolNames() {
        #expect(MCPToolBuilder.sanitize("view-tree") == "view_tree")
        #expect(MCPToolBuilder.sanitize("Year Report") == "year_report")
        #expect(MCPToolBuilder.sanitize("a.b/c") == "a_b_c")
        #expect(MCPToolBuilder.sanitize("already_ok9") == "already_ok9")
    }

    @Test func plansOverviewActionQueryAndTailTools() {
        let plan = MCPToolBuilder.plan(from: fixtureManifests())
        let names = Set(plan.map(\.name))
        #expect(names.contains("porthole_overview"))
        #expect(names.contains("act_test_echo"))
        #expect(names.contains("act_test_wipe"))
        #expect(names.contains("query_test_rows"))
        #expect(names.contains("query_test_ticks"))
        #expect(names.contains("tail_test_ticks"))
        // A non-subscribable source gets no tail tool.
        #expect(!names.contains("tail_test_rows"))
    }

    @Test func targetsMapToRefs() {
        let plan = MCPToolBuilder.plan(from: fixtureManifests())
        let echo = plan.first { $0.name == "act_test_echo" }
        #expect(echo?.target == .action(PortholeActionRef(connector: "test", action: "echo")))
        let rows = plan.first { $0.name == "query_test_rows" }
        #expect(rows?.target == .query(PortholeDataSourceRef(connector: "test", source: "rows")))
        let ticks = plan.first { $0.name == "tail_test_ticks" }
        #expect(ticks?.target == .tail(PortholeDataSourceRef(connector: "test", source: "ticks")))
    }

    @Test func destructiveActionNotedInDescription() {
        let plan = MCPToolBuilder.plan(from: fixtureManifests())
        let wipe = plan.first { $0.name == "act_test_wipe" }
        #expect(wipe?.description.contains("Destructive") == true)
    }

    @Test func queryToolSchemaAddsLimitAndCursor() throws {
        let plan = MCPToolBuilder.plan(from: fixtureManifests())
        let rows = try #require(plan.first { $0.name == "query_test_rows" })
        let properties = rows.inputSchema["properties"]?.objectValue ?? [:]
        #expect(properties["count"] != nil)
        #expect(properties["limit"] != nil)
        #expect(properties["cursor"] != nil)
    }
}
