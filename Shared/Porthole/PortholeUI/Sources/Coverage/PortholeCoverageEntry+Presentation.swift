import PortholeCore

extension PortholeCoverageEntry {
    var statusTitle: String {
        switch state {
            case .callable: "Active · Callable"
            case .inspectableSource: "Active · Inspectable source"
            case .unsupported: "Active · Unsupported"
            case .inactive: "Inactive in this build"
            case .sourceOnly: "Source only"
            case .excluded: "Excluded from generation"
        }
    }

    var statusReason: String {
        switch state {
            case .callable: "A compiled handler is registered. Its effect still determines whether a call needs approval."
            case .inspectableSource: "This declaration is registered for inspection. It has no callable handler."
            case let .unsupported(reason), let .sourceOnly(reason), let .excluded(reason): reason
            case .inactive: "This declaration has no registration in the installed build. Its compilation conditions and generation plan appear below."
        }
    }

    var plannedSupportTitle: String {
        switch declaration.plannedAvailability {
            case .callable: "Planned callable"
            case .inspectable: "Planned inspectable source"
            case .unsupported: "Planned unsupported"
        }
    }

    var plannedSupportReason: String? {
        if case let .unsupported(reason) = declaration.plannedAvailability { reason } else { nil }
    }

    func sourceEvidence(in scope: PortholeScopeToken) -> PortholeEvidenceReference? {
        guard let source = declaration.source,
              let hash = declaration.sourceSHA256 else { return nil }
        return .source(.init(scope: scope, path: source.path, line: source.line, sha256: hash))
    }

    /// A planned binding never grants an invocation affordance.
    func callableCapability(in capabilities: [PortholeCapability]) -> PortholeCapability? {
        guard case .callable = state, let installedCapabilityID else { return nil }
        return capabilities.first { $0.id == installedCapabilityID && $0.availability == .callable }
    }
}
