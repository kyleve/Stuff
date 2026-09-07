#if DEBUG
    @testable import Flyover
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
    }
#endif
