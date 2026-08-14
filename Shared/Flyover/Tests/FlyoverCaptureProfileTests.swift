#if DEBUG
    @testable import Flyover
    import Testing

    struct FlyoverCaptureProfileTests {
        @Test func emptyRequestUsesPhoneLight() throws {
            #expect(try FlyoverCaptureProfile.parse([]) == [.phoneLight])
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
