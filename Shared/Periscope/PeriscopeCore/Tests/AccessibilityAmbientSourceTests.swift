#if canImport(UIKit)
    import Foundation
    import PeriscopeCore
    import Testing
    import UIKit

    struct AccessibilityAmbientSourceTests {
        @Test func startLogsTheCurrentSettingsSummary() async {
            let sink = CapturingSink()
            let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
            system.startAmbientSource(AccessibilityAmbientSource())

            // The summary hops to the main actor; wait for it rather than
            // racing it. The simulator has nothing enabled.
            let summarized = await waitUntil {
                sink.records.contains { $0.message == "accessibility: none enabled" }
            }
            #expect(summarized)
        }

        /// A toggle must re-report the full summary — the value folds into
        /// the snapshot under one kind, so a single-setting delta would
        /// replace the complete accessibility state.
        @Test func settingChangesReReportTheFullSummary() async {
            let sink = CapturingSink()
            let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
            system.startAmbientSource(AccessibilityAmbientSource())

            NotificationCenter.default.post(
                name: UIAccessibility.voiceOverStatusDidChangeNotification,
                object: nil,
            )

            // The observer runs on the main queue; poll for delivery. The
            // simulator has nothing enabled, so the change event's summary
            // matches the baseline's — two records, one shape.
            let logged = await waitUntil {
                sink.records.count(where: { $0.message == "accessibility: none enabled" }) >= 2
            }
            #expect(logged)

            system.stopAmbientSources()
            NotificationCenter.default.post(
                name: UIAccessibility.voiceOverStatusDidChangeNotification,
                object: nil,
            )
            await system.flush()
            #expect(
                sink.records.count(where: { $0.message == "accessibility: none enabled" }) == 2,
            )
        }
    }
#endif
