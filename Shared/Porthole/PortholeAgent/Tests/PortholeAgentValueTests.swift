import AI
@testable import PortholeAgent
import PortholeCore
import Testing

struct PortholeAgentValueTests {
    @Test func neverRoundsInt64() throws {
        #expect(try PortholeAgentValue.output(.integer(.max)) == .string("9223372036854775807"))
        #expect(try PortholeAgentValue.output(.integer(.min)) == .string("-9223372036854775808"))
        #expect(try PortholeAgentValue
            .output(.unsignedInteger(.max)) == .string("18446744073709551615"))
        #expect(throws: PortholeAgentError.unsafeInteger) {
            try PortholeAgentValue.input(.number(9_007_199_254_740_992))
        }
        #expect(try PortholeAgentValue.input(.number(42)) == .integer(42))
        #expect(try PortholeAgentValue.input(.number(4.5)) == .number(4.5))
    }
}
