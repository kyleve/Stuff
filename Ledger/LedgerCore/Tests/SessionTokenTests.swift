@_spi(Testing) import LedgerCore
import Testing

struct SessionTokenTests {
    @Test func derivesUserIDFromJWTSubAndStripsProvider() {
        let jwt = DashboardFixture.jwt(sub: "auth0|user_01ABC")
        let token = SessionToken(rawToken: jwt)
        #expect(token?.cookieValue == "user_01ABC::\(jwt)")
    }

    @Test func keepsAnAlreadyFormedUserIDColonColonJWTVerbatim() {
        let jwt = DashboardFixture.jwt(sub: "auth0|user_01ABC")
        let combined = "user_01ABC::\(jwt)"
        #expect(SessionToken(rawToken: combined)?.cookieValue == combined)
    }

    @Test func subWithoutProviderPrefixIsUsedAsIs() {
        let jwt = DashboardFixture.jwt(sub: "user_bare")
        #expect(SessionToken(rawToken: jwt)?.cookieValue == "user_bare::\(jwt)")
    }

    @Test func nonJWTIsKeptVerbatimSoItSurfacesAsAn401() {
        // Not parseable as a JWT: kept as-is rather than dropped, so it fails
        // honestly at the API instead of silently vanishing.
        #expect(SessionToken(rawToken: "not-a-jwt")?.cookieValue == "not-a-jwt")
    }

    @Test func emptyIsNil() {
        #expect(SessionToken(rawToken: "   ") == nil)
    }
}
