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

    /// A `get-filtered-usage-events` body — with fields Ledger ignores, to
    /// prove decoding tolerates them.
    static let usageEventsJSON = """
    {
      "totalUsageEventsCount": 40,
      "usageEventsDisplay": [
        {
          "timestamp": "1784939309797",
          "model": "claude-opus-5-thinking-high",
          "kind": "USAGE_EVENT_KIND_USAGE_BASED",
          "requestsCosts": 53.69,
          "usageBasedCosts": "$5.37",
          "isTokenBasedCall": true,
          "chargedCents": 536.9,
          "isChargeable": true
        },
        {
          "timestamp": "1784939000000",
          "model": "claude-opus-4-8-thinking-high",
          "kind": "USAGE_EVENT_KIND_USAGE_BASED",
          "usageBasedCosts": "$5.08",
          "chargedCents": 508.28
        },
        {
          "timestamp": "1784938000000",
          "model": "github_bugbot",
          "usageBasedCosts": "$0.00",
          "chargedCents": 0
        }
      ]
    }
    """
}
