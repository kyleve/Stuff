import Foundation
import SQLite3

/// Resolves the Cursor session token automatically from the locally installed
/// Cursor app, so the menu-bar app can reuse the session you're already signed
/// into without anything to paste. The seam is a protocol so tests inject a
/// fixed token instead of reading a real database.
public protocol SessionTokenSource: Sendable {
    /// The current auto-detected token, or `nil` when none is available
    /// (Cursor not installed, signed out, or the store moved).
    func currentToken() -> SessionToken?
}

/// Reads the Cursor IDE's stored access token from its `state.vscdb`
/// key-value store (`ItemTable`, key `cursorAuth/accessToken`) and normalizes
/// it into a ``SessionToken``.
///
/// The database is opened **read-only**; Cursor may hold it open, so we never
/// write or lock it. A missing file, missing key, or open failure is a plain
/// `nil` (auto-detect simply isn't available) — not a thrown error.
public struct CursorLocalTokenSource: SessionTokenSource {
    private let databaseURL: URL
    private let key: String

    /// The default location of Cursor's global state store on macOS.
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                isDirectory: false,
            )
    }

    public init(
        databaseURL: URL = CursorLocalTokenSource.defaultDatabaseURL,
        key: String = "cursorAuth/accessToken",
    ) {
        self.databaseURL = databaseURL
        self.key = key
    }

    public func currentToken() -> SessionToken? {
        guard let raw = readValue(forKey: key), let token = SessionToken(rawToken: raw) else {
            return nil
        }
        return token
    }

    /// Reads a single `ItemTable.value` for `key`, or `nil` on any failure.
    private func readValue(forKey key: String) -> String? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

        var db: OpaquePointer?
        // Read-only, and don't create the file if it's missing.
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT value FROM ItemTable WHERE key = ? LIMIT 1",
            -1,
            &statement,
            nil,
        ) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        // SQLITE_TRANSIENT tells SQLite to copy the bound string.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_text(statement, 0)
        else {
            return nil
        }
        return String(cString: bytes)
    }
}
