import Foundation
import SwiftData

extension SwiftDataStore {
    /// Read fresh committed metadata as well as the current transaction's pending lower bounds.
    public func requiredDataCompatibilityVersion() throws -> DataCompatibilityVersion {
        do {
            return try max(
                Self.requiredVersion(in: ModelContext(modelContainer)),
                Self.requiredVersion(in: compatibilityContext()),
            )
        } catch let error as DataCompatibilityError { throw error }
        catch { throw DataCompatibilityError.verificationFailed(error.localizedDescription) }
    }

    public func validateDataAccess() throws {
        try assertDataCompatible()
    }

    func assertDataCompatible() throws {
        try assertDataCompatible(in: compatibilityContext())
    }

    func assertDataCompatible(in context: ModelContext) throws {
        try DataAccessPermit.current?.validate()
        let required: DataCompatibilityVersion
        do {
            required = try max(
                Self.requiredVersion(in: ModelContext(modelContainer)),
                Self.requiredVersion(in: context),
            )
        } catch { throw DataCompatibilityError.verificationFailed(error.localizedDescription) }
        guard supportedCompatibilityVersion >= required
        else { throw DataCompatibilityError.updateRequired(required) }
        markDomainAccess()
    }

    private static func requiredVersion(in context: ModelContext) throws
        -> DataCompatibilityVersion
    {
        let imported = try compatibilityRequirements(in: context).map(\.version).max() ?? .initial
        let authority = try RecordingAuthority.resolve(commits: authorityCommits(in: context))
        return max(imported, authority.requiredVersion)
    }

    #if DEBUG
        @_spi(Testing)
        public func setSupportedDataCompatibilityVersionForTesting(
            _ version: DataCompatibilityVersion,
        ) {
            supportedCompatibilityVersion = version
        }
    #endif
}
