import Foundation

extension RecordingHistorySelection {
    /// These periods cannot connect a device's selected observations into one physical track.
    /// Ordinary recording silence remains available to the flight policy's corroborated-gap rules.
    func trajectoryExclusions(for deviceID: RecordingDeviceID) -> [RecordingPeriod] {
        let controlled = controls.compactMap { segment -> RecordingPeriod? in
            let excludes: Bool = switch segment.resolution {
                case let .selected(selected): selected != deviceID
                case .unresolved: true
                case let .automatic(automatic):
                    switch automatic.eligibility(of: deviceID) {
                        case .eligible: false
                        case .ignored, .removed, .conflict, .incomplete: true
                    }
            }
            return excludes ? segment.period : nil
        }
        let assessed = segments.compactMap { segment -> RecordingPeriod? in
            let excludes: Bool = switch segment.resolution {
                case let .chosen(selected): selected != deviceID
                case .unresolved: true
                case let .automatic(selection):
                    switch selection {
                        case .noEvidence: false
                        case let .onlyAvailableDevice(selected),
                             let .movingOverStationary(selected):
                            selected != deviceID
                        case let .agreement(selected), let .uncertain(selected):
                            !selected.contains(deviceID)
                        case .conflict: true
                    }
            }
            return excludes ? segment.period : nil
        }
        // A chosen source can have an unknown calendar assignment without changing its chosen
        // segment. The point's unresolved period still breaks eligibility for trajectory inference.
        return RecordingPeriod.union(controlled + assessed + issues.map(\.period))
    }
}
