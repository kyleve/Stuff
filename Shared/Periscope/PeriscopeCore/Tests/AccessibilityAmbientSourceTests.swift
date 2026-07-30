#if canImport(UIKit)
    import Foundation
    import PeriscopeCore
    import Testing
    import UIKit

    struct AccessibilityAmbientSourceTests {
        /// Every observed setting, as a named boolean — the simulator has
        /// nothing enabled, so all eight read false.
        private var allDisabled: [String: AmbientValue] {
            [
                "voiceover": false,
                "switch-control": false,
                "reduce-motion": false,
                "reduce-transparency": false,
                "bold-text": false,
                "darker-colors": false,
                "invert-colors": false,
                "grayscale": false,
            ]
        }

        private func summaries(in sink: CapturingSink) -> [[String: AmbientValue]] {
            sink.records
                .compactMap { $0.event as? AmbientEvent }
                .filter { $0.kind == .accessibility }
                .map(\.value)
        }

        @Test func startLogsEveryCurrentSettingAsOneValue() async {
            let sink = CapturingSink()
            let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
            system.startAmbientSource(AccessibilityAmbientSource())

            // The summary hops to the main actor; wait for it rather than
            // racing it.
            let summarized = await waitUntil {
                summaries(in: sink).contains(allDisabled)
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
                summaries(in: sink).count(where: { $0 == allDisabled }) >= 2
            }
            #expect(logged)

            system.stopAmbientSources()
            NotificationCenter.default.post(
                name: UIAccessibility.voiceOverStatusDidChangeNotification,
                object: nil,
            )
            await system.flush()
            #expect(summaries(in: sink).count == 2)
        }
    }
#endif
