import Foundation

/// Replays event sequences and optionally auto-completes effects for scenario tests.
enum ServicesMachineReplay {
    struct Trace: Equatable {
        var snapshots: [ServicesSnapshot]
        var effects: [ServiceEffect]

        init(snapshots: [ServicesSnapshot], effects: [ServiceEffect]) {
            self.snapshots = snapshots
            self.effects = effects
        }

        var final: ServicesSnapshot {
            snapshots.last ?? .initial
        }
    }

    /// Feed external events only; effects accumulate but do not auto-complete.
    static func trace(events: [ServicesEvent]) -> Trace {
        var snapshot = ServicesSnapshot.initial
        var snapshots: [ServicesSnapshot] = [snapshot]
        var allEffects: [ServiceEffect] = []
        for event in events {
            let step = ServicesMachine.reduce(snapshot, event)
            snapshot = step.snapshot
            snapshots.append(snapshot)
            allEffects.append(contentsOf: step.effects)
        }
        return Trace(snapshots: snapshots, effects: allEffects)
    }

    /// Alternate external events with synthetic effect completions until quiescent.
    static func runToQuiescence(events: [ServicesEvent]) -> Trace {
        var snapshot = ServicesSnapshot.initial
        var snapshots: [ServicesSnapshot] = [snapshot]
        var allEffects: [ServiceEffect] = []
        var queue = events

        while !queue.isEmpty {
            let event = queue.removeFirst()
            let step = ServicesMachine.reduce(snapshot, event)
            snapshot = step.snapshot
            snapshots.append(snapshot)
            allEffects.append(contentsOf: step.effects)
            queue.insert(contentsOf: completions(for: step.effects, snapshot: snapshot), at: 0)
        }
        return Trace(snapshots: snapshots, effects: allEffects)
    }

    private static func completions(
        for effects: [ServiceEffect],
        snapshot _: ServicesSnapshot,
    ) -> [ServicesEvent] {
        effects.flatMap { effect -> [ServicesEvent] in
            switch effect {
                case .startIngestor:
                    [.ingestorStartFinished]
                case .stopIngestor:
                    [.ingestorStopFinished]
                case .beginIngestorQuiesce:
                    [.ingestorQuiesceFinished]
                case .beginStorePerform:
                    []
                case .commitStoreWrite:
                    []
                case let .publishWidgetsAfterIngest(sample):
                    [
                        .reconcileStepFinished(.invalidateIssues),
                        .reconcileStepFinished(.reconcileReminders),
                        .reconcileStepFinished(.reconcileIssueAlerts),
                        .reconcileStepFinished(.publishWidgetsAfterIngest(sample)),
                        .storeChangesPinged,
                    ]
                case .invalidateIssueScanner:
                    [.reconcileStepFinished(.invalidateIssues)]
                case .reconcileReminders:
                    [.reconcileStepFinished(.reconcileReminders)]
                case .reconcileIssueAlerts:
                    [.reconcileStepFinished(.reconcileIssueAlerts)]
                case .publishWidgets:
                    [.reconcileStepFinished(.publishWidgets), .storeChangesPinged]
                case .pingStoreChanges:
                    [.storeChangesPinged]
                case .eraseAllData:
                    [.eraseAllDataFinished]
                case .syncAuthorization:
                    [.launchStepFinished(.syncAuthorization)]
                case .reconcileTracking:
                    [.launchStepFinished(.reconcileTracking)]
                case .captureTodayIfNeeded:
                    [.launchStepFinished(.captureTodayIfNeeded)]
                case .applyReminderConfiguration:
                    [.launchStepFinished(.applyReminderConfiguration)]
                case .applySummaryConfiguration:
                    [.launchStepFinished(.applySummaryConfiguration)]
                case .applyIssueAlertConfiguration:
                    [.launchStepFinished(.applyIssueAlertConfiguration)]
                case .refreshWidgetSnapshot:
                    [.launchStepFinished(.refreshWidgetSnapshot)]
                case .persistTrackingDesired, .publishTracking,
                     .completeIngestorQuiesce, .invalidateIssueScannerAfterReset:
                    []
            }
        }
    }
}
