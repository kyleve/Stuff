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

enum SpendFixture {
    /// Builds a member with the fields tests care about; the rest default.
    static func member(
        email: String,
        spendCents: Double = 0,
        includedSpendCents: Double? = nil,
        overallSpendCents: Double? = nil,
        fastPremiumRequests: Int? = nil,
    ) -> MemberSpend {
        MemberSpend(
            userId: "user_\(email)",
            name: email,
            email: email,
            spendCents: spendCents,
            includedSpendCents: includedSpendCents,
            overallSpendCents: overallSpendCents,
            fastPremiumRequests: fastPremiumRequests,
        )
    }

    /// A realistic `/teams/spend` response body, including fields Ledger does
    /// not model (they must be ignored, not fail decoding).
    static let responseJSON = """
    {
      "teamMemberSpend": [
        {
          "userId": "user_ABC",
          "name": "Alex Admin",
          "email": "alex@company.com",
          "role": "owner",
          "spendCents": 4212.5,
          "includedSpendCents": 8000.0,
          "overallSpendCents": 12212.5,
          "fastPremiumRequests": 143,
          "profilePictureUrl": null,
          "monthlyLimitDollars": null,
          "hardLimitOverrideDollars": 0
        },
        {
          "userId": "user_DEF",
          "name": "Blair Member",
          "email": "blair@company.com",
          "role": "member",
          "spendCents": 0,
          "includedSpendCents": 150.75,
          "fastPremiumRequests": 2
        }
      ],
      "totalMembers": 2,
      "totalPages": 1,
      "subscriptionCycleStart": 1708992000000
    }
    """
}
