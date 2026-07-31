import Testing
import WhereSurface

struct WhereSurfaceChangeNotificationTests {
    @Test func notificationNameIsStableAcrossProcesses() {
        #expect(WhereSurfaceChangeNotification.name == "com.stuff.where.surface.changed")
    }
}
