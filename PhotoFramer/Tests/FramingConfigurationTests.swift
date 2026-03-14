import Testing

@testable import PhotoFramer

@Suite
struct FramingConfigurationTests {

    @Test func defaultConfigurationUseCropToFill() {
        let config = FramingConfiguration.default
        #expect(config.mode == .cropToFill)
    }

    @Test func defaultConfigurationResolution() {
        let config = FramingConfiguration.default
        #expect(config.outputResolution == 3000)
    }

    @Test func allFramingModesExist() {
        #expect(FramingMode.allCases.count == 2)
    }

    @Test func framingModeIds() {
        let ids = Set(FramingMode.allCases.map(\.id))
        #expect(ids.count == 2)
    }
}
