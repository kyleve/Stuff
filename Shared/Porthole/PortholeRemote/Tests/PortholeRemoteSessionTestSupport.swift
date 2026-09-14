import Foundation
import PortholeCore
@testable import PortholeRemote

/// A native executor accepts independent scopes without retaining a second observation ledger.
actor PortholeRemoteLedgerTestExecutor: PortholeExecuting, PortholeObservationOwning {
    func capabilities(in _: PortholeScopeToken) -> [PortholeCapability] {
        []
    }

    func invoke(_ invocation: PortholeInvocation) throws -> PortholeValue {
        if invocation.capabilityID == PortholeObservationCapabilities.stop { return .null }
        guard invocation.capabilityID == PortholeObservationCapabilities.start,
              let value = invocation.arguments["request"]
        else { throw PortholeRemoteError.invalidMessage }
        return try .encoding(value.decode(PortholeObservationRequest.self).reference)
    }

    func stopObservations(ownedBy _: PortholeObservationOwnerID) {}
}
