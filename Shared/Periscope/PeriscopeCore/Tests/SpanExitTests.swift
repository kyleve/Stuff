import Foundation
import PeriscopeCore
import Testing

struct SpanExitTests {
    @Test func staticsCarryTheirModes() {
        #expect(SpanExit.success.mode == .success)
        #expect(SpanExit.success.reason == nil)
        #expect(SpanExit.failure("card declined").reason == "card declined")
        #expect(SpanExit.cancelled("user backed out").mode == .cancelled)
        #expect(SpanExit.superseded.mode == .superseded)
        #expect(SpanExit.orphaned.mode == .orphaned)
    }

    @Test func expiredCarriesItsBudget() {
        let exit = SpanExit.expired(budget: .seconds(30))
        #expect(exit.mode == .expired)
        #expect(exit.reason?.contains("budget") == true)
    }

    @Test func exitRoundTripsThroughCodable() throws {
        let exit = SpanExit.failure("network timeout")
        let data = try JSONEncoder().encode(exit)
        let decoded = try JSONDecoder().decode(SpanExit.self, from: data)
        #expect(decoded == exit)
    }

    @Test func lifetimeRoundTripsThroughCodable() throws {
        for lifetime in [
            SpanLifetime.scoped,
            .bounded(budget: .milliseconds(1500)),
            .indefinite,
        ] {
            let data = try JSONEncoder().encode(lifetime)
            let decoded = try JSONDecoder().decode(SpanLifetime.self, from: data)
            #expect(decoded == lifetime)
        }
    }

    @Test func relaunchPolicyRoundTripsThroughCodable() throws {
        for policy in [SpanRelaunchPolicy.endsWithProcess, .survivesRelaunch] {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(SpanRelaunchPolicy.self, from: data)
            #expect(decoded == policy)
        }
    }
}
