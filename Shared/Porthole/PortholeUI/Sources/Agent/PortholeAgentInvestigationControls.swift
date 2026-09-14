import Foundation
import PortholeAgent
import PortholeCore

/// The selected transcript and current capture remain separate during navigation.
@MainActor
struct PortholeAgentInvestigationControls {
    let selected: PortholeAgentInvestigation
    let available: [PortholeAgentInvestigation]
    let originalContext: PortholeValue
    let currentCapture: PortholeAgentOrigin
    let create: @MainActor () throws -> Void
    let resume: @MainActor (UUID) throws -> Void
    let continueWithContext: @MainActor () async throws -> Void
}
