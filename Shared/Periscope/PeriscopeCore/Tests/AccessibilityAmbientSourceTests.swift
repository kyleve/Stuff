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

        @Test func settingChangesLogTheCurrentState() async {
            let sink = CapturingSink()
            let system = Periscope(configuration: Periscope.Configuration(), sinks: [sink])
            system.startAmbientSource(AccessibilityAmbientSource())

            NotificationCenter.default.post(
                name: UIAccessibility.voiceOverStatusDidChangeNotification,
                object: nil,
            )

            // The observer runs on the main queue; poll for delivery. The
            // simulator reports VoiceOver off.
            let logged = await waitUntil {
                sink.records.contains { $0.message == "accessibility: voiceover: off" }
            }
            #expect(logged)

            system.stopAmbientSources()
            NotificationCenter.default.post(
                name: UIAccessibility.voiceOverStatusDidChangeNotification,
                object: nil,
            )
            await system.flush()
            #expect(
                sink.records.count(where: { $0.message == "accessibility: voiceover: off" }) == 1,
            )
        }
    }
#endif
