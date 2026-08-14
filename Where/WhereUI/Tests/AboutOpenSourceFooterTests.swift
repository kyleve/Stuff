import Testing
@testable import WhereUI

struct AboutOpenSourceFooterTests {
    @Test func linksToTheCanonicalProjectRepository() {
        #expect(AboutOpenSourceFooter.projectURL
            .absoluteString == "https://github.com/kyleve/Stuff")
    }
}
