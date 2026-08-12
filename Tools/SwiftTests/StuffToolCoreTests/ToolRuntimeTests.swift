@testable import StuffToolCore
import Testing

struct ToolRuntimeTests {
    @Test
    func constructsEveryProductionService() {
        let runtime = ToolRuntime()

        _ = runtime.testService()
        _ = runtime.profileService()
        _ = runtime.flakyService()
        _ = runtime.simulatorService()
        _ = runtime.iconsService()
        _ = runtime.whereInstallService()
        _ = runtime.ledgerInstallService()
    }
}
