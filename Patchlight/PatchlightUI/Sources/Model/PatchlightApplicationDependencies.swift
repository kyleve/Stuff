import Foundation
import PatchlightCore
import StuffCore

/// Process-owned inputs from the thin app host. Account-scoped resources are
/// still created only after GitHub identifies the signed-in user.
public struct PatchlightApplicationDependencies: Sendable {
    public let githubConfiguration: GitHubAppConfiguration
    public let credentialStore: any CredentialStore
    public let transport: any PatchlightHTTPTransport
    public let accountsRootURL: URL
    public let cacheCapacity: CacheCapacity

    public init(
        githubConfiguration: GitHubAppConfiguration,
        credentialStore: any CredentialStore,
        transport: any PatchlightHTTPTransport,
        accountsRootURL: URL,
        cacheCapacity: CacheCapacity,
    ) {
        self.githubConfiguration = githubConfiguration
        self.credentialStore = credentialStore
        self.transport = transport
        self.accountsRootURL = accountsRootURL
        self.cacheCapacity = cacheCapacity
    }

    public static func production(bundle: Bundle) -> PatchlightApplicationDependencies {
        let clientID = bundle
            .object(forInfoDictionaryKey: "PatchlightGitHubClientID") as? String ?? ""
        let appSlug = bundle.object(forInfoDictionaryKey: "PatchlightGitHubAppSlug") as? String ?? ""
        return PatchlightApplicationDependencies(
            githubConfiguration: GitHubAppConfiguration(clientID: clientID, appSlug: appSlug),
            credentialStore: SystemCredentialStore(service: "com.stuff.patchlight"),
            transport: URLSessionPatchlightHTTPTransport(),
            accountsRootURL: PatchlightScope.defaultRootURL,
            cacheCapacity: .fiveGB,
        )
    }

    #if DEBUG
        @_spi(Testing)
        public static var preview: PatchlightApplicationDependencies {
            PatchlightApplicationDependencies(
                githubConfiguration: GitHubAppConfiguration(clientID: "", appSlug: ""),
                credentialStore: SystemCredentialStore(service: "com.stuff.patchlight.preview"),
                transport: URLSessionPatchlightHTTPTransport(),
                accountsRootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("PatchlightPreviews", isDirectory: true),
                cacheCapacity: .oneGB,
            )
        }
    #endif
}
