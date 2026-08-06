import Foundation
@_spi(Testing) import LedgerCore
import SQLite3
import Testing

struct SessionTokenSourceTests {
    @Test func returnsNilWhenTheDatabaseIsMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).vscdb")
        let source = CursorLocalTokenSource(databaseURL: missing)
        #expect(source.currentToken() == nil)
    }

    @Test func readsAndDerivesTheTokenFromAStateStore() throws {
        let jwt = DashboardFixture.jwt(sub: "auth0|user_STATE")
        let url = try makeStateDB(accessToken: jwt)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = CursorLocalTokenSource(databaseURL: url)
        #expect(source.currentToken()?.cookieValue == "user_STATE::\(jwt)")
    }

    @Test func returnsNilWhenTheKeyIsAbsent() throws {
        let url = try makeStateDB(accessToken: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = CursorLocalTokenSource(databaseURL: url)
        #expect(source.currentToken() == nil)
    }

    /// Creates a minimal `state.vscdb`-shaped SQLite file with an `ItemTable`,
    /// optionally seeding `cursorAuth/accessToken`.
    private func makeStateDB(accessToken: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-\(UUID().uuidString).vscdb")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(
            db,
            "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)",
            nil,
            nil,
            nil,
        ) == SQLITE_OK)
        if let accessToken {
            let sql = "INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', '\(accessToken)')"
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        return url
    }
}
