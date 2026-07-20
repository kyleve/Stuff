import Foundation
@_spi(Testing) import LedgerCore

/// A `LoginItemBackend` that records register/unregister/open calls in memory
/// and can be told to fail, so login-item wiring is testable without touching
/// the real `SMAppService`.
@MainActor
final class LoginItemRecorder: LoginItemBackend {
    private(set) var status: LoginItemStatus
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openCount = 0

    /// When set, both `register()` and `unregister()` throw it (and leave
    /// `status` unchanged), simulating an `SMAppService` failure.
    var failure: (any Error)?

    init(status: LoginItemStatus = .notRegistered, failure: (any Error)? = nil) {
        self.status = status
        self.failure = failure
    }

    func register() throws {
        registerCount += 1
        if let failure { throw failure }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let failure { throw failure }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openCount += 1
    }
}

/// A stand-in error for login-item failure injection.
struct LoginItemTestError: Error {}

enum DashboardFixture {
    /// Builds a signed-looking JWT (unsigned; only the payload matters) whose
    /// `sub` is `sub`. base64url, no padding.
    static func jwt(sub: String) -> String {
        func segment(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(segment(["alg": "HS256"])).\(segment(["sub": sub])).signature"
    }

    /// A trimmed but realistic `/api/usage-summary` body.
    static let usageSummaryJSON = """
    {
      "billingCycleStart": "2026-07-04T18:16:08.000Z",
      "billingCycleEnd": "2026-08-04T18:16:08.000Z",
      "membershipType": "ultra",
      "limitType": "user",
      "isUnlimited": false,
      "individualUsage": {
        "plan": {
          "enabled": true,
          "used": 40000,
          "limit": 40000,
          "remaining": 0,
          "breakdown": { "included": 40000, "bonus": 12158, "total": 52158 },
          "autoPercentUsed": 0.69,
          "apiPercentUsed": 100,
          "totalPercentUsed": 20.87
        },
        "onDemand": { "enabled": true, "used": 315609, "limit": null, "remaining": null }
      },
      "teamUsage": {}
    }
    """

    /// A `get-aggregated-usage-events` body — token fields are strings on the wire.
    static let aggregatedJSON = """
    {
      "aggregations": [
        {
          "modelIntent": "claude-opus-4-8-thinking-xhigh",
          "inputTokens": "1846267",
          "outputTokens": "2088128",
          "cacheWriteTokens": "12919376",
          "cacheReadTokens": "316915979",
          "totalCents": 28929.15,
          "tier": 1
        },
        {
          "modelIntent": "composer-2.5-fast",
          "inputTokens": "8294988",
          "outputTokens": "809154",
          "cacheReadTokens": "86124639",
          "totalCents": 8008.45,
          "tier": 2
        }
      ],
      "totalInputTokens": "10141255",
      "totalOutputTokens": "2897282",
      "totalCostCents": 36937.6
    }
    """
}
