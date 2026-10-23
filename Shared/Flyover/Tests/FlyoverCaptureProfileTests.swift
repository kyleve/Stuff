#if DEBUG
    import CoreGraphics
    @testable import Flyover
    import SnapshotKit
    import Testing

    struct FlyoverCaptureProfileTests {
        @Test func emptyRequestUsesLightAndDarkPhones() throws {
            #expect(try FlyoverCaptureProfile.parse([]) == [.phoneLight, .phoneDark])
        }

        @Test func emptyTypedRequestUsesLightAndDarkPhones() {
            #expect(FlyoverCaptureProfile.orderedUnique([]) == [.phoneLight, .phoneDark])
        }

        @Test func preservesFirstOccurrenceOrderAndRemovesDuplicates() throws {
            let profiles = try FlyoverCaptureProfile.parse([
                "phone-dark",
                "phone-light",
                "phone-dark",
            ])

            #expect(profiles == [.phoneDark, .phoneLight])
        }

        @Test func rejectsUnknownProfile() {
            #expect(throws: FlyoverExportError.unknownProfile("system")) {
                try FlyoverCaptureProfile.parse(["system"])
            }
        }

        @Test func deviceProfilesDeclareTruthfulAdaptiveLayoutTraits() {
            let phone = FlyoverCaptureProfile.phoneLight.configuration(
                viewport: .device,
                captureExtent: .viewport,
            )
            let tablet = FlyoverCaptureProfile.tabletLight.configuration(
                viewport: .device,
                captureExtent: .viewport,
            )
            let landscape = FlyoverCaptureProfile.phoneLandscape.configuration(
                viewport: .device,
                captureExtent: .viewport,
            )

            #expect(phone.layoutTraits == .phonePortrait)
            #expect(tablet.layoutTraits == .tabletPortrait)
            #expect(landscape.layoutTraits == .phoneLandscape)
        }

        @Test func fixedViewportRetainsItsSizeWhileProfileLayoutTraitsApply() {
            let fixedSize = CGSize(width: 320, height: 180)
            let configuration = FlyoverCaptureProfile.tabletLight.configuration(
                viewport: .fixed(fixedSize),
                captureExtent: .viewport,
            )

            #expect(configuration.device.size == .fixed(fixedSize))
            #expect(configuration.layoutTraits == .tabletPortrait)
        }
    }
#endif
