import Foundation

/// A Cursor dashboard session credential, normalized to the exact value the
/// `WorkosCursorSessionToken` cookie needs: `"<userId>::<jwt>"`.
///
/// The dashboard API rejects a bare JWT (HTTP 401) — the cookie must carry the
/// user id prefix. The Cursor app stores only the raw JWT (in `state.vscdb` /
/// Keychain), so ``init(rawToken:)`` derives the prefix from the JWT's `sub`
/// claim (`"auth0|user_ABC"` → `user_ABC`). A value the user pastes may already
/// be in `userId::jwt` form, in which case it's used as-is.
public struct SessionToken: Equatable, Sendable {
    /// The ready-to-send cookie value (`userId::jwt`).
    public let cookieValue: String

    /// Wraps an already-formed `userId::jwt` cookie value verbatim.
    public init(cookieValue: String) {
        self.cookieValue = cookieValue
    }

    /// Builds the cookie value from whatever the user or the local Cursor app
    /// provides: a `userId::jwt` string is kept as-is; a bare JWT gets its
    /// `userId` derived from the `sub` claim and prepended. Returns `nil` for
    /// an empty string.
    public init?(rawToken: String) {
        let trimmed = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("::") {
            cookieValue = trimmed
            return
        }
        guard let userID = Self.userID(fromJWT: trimmed) else {
            // Not a JWT we can parse — keep it verbatim so a mis-paste surfaces
            // as an honest 401 rather than being silently dropped.
            cookieValue = trimmed
            return
        }
        cookieValue = "\(userID)::\(trimmed)"
    }

    /// Extracts the user id from a JWT's `sub` claim, stripping any
    /// `"provider|"` prefix (e.g. `"auth0|user_ABC"` → `"user_ABC"`).
    static func userID(fromJWT jwt: String) -> String? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        guard let payload = base64URLDecoded(String(segments[1])) else { return nil }
        guard
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let sub = object["sub"] as? String
        else { return nil }
        return sub.contains("|") ? String(sub.split(separator: "|").last ?? "") : sub
    }

    /// Decodes a base64url segment (no padding, `-`/`_` alphabet) to `Data`.
    private static func base64URLDecoded(_ input: String) -> Data? {
        var base64 = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
