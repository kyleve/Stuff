/// Export permission for one destination, independent of each field's classification.
/// A sink must apply this policy before encoding a value. This model does not filter raw Codable
/// payloads.
public struct LogExportPolicy: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case baseline
        case diagnostic
    }

    public var mode: Mode
    public private(set) var enabledControls: Set<LogExportControl>

    public init(mode: Mode, enabledControls: Set<LogExportControl>) {
        self.mode = mode
        self.enabledControls = enabledControls
    }

    /// Each known or consumer-defined control is an independent switch, initially off.
    public subscript(control: LogExportControl) -> Bool {
        get { enabledControls.contains(control) }
        set {
            if newValue {
                enabledControls.insert(control)
            } else {
                enabledControls.remove(control)
            }
        }
    }

    /// Supports one UI switch over an explicit group without changing unrelated grants.
    /// There is deliberately no wildcard that grants future or consumer-defined controls.
    public mutating func setEnabled(_ enabled: Bool, for controls: Set<LogExportControl>) {
        if enabled {
            enabledControls.formUnion(controls)
        } else {
            enabledControls.subtract(controls)
        }
    }

    public func allows(_ requirements: LogExportRequirements) -> Bool {
        switch requirements {
            case .never:
                false
            case let .baseline(controls):
                controls.isSubset(of: enabledControls)
            case let .diagnostic(controls):
                mode == .diagnostic && controls.isSubset(of: enabledControls)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case enabledControls = "enabled_controls"
    }
}
