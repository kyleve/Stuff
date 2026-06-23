import LogKit
import Testing

#if DEBUG
    @Test
    func channelRecordsEachLevelIntoStore() {
        let store = LogStore()
        let channel = LogChannel(subsystem: "com.test", category: "Sample", store: store)

        channel.debug("d")
        channel.info("i")
        channel.notice("n")
        channel.warning("w")
        channel.error("e")
        channel.fault("f")

        let entries = store.snapshot()
        #expect(entries.map(\.level) == [.debug, .info, .notice, .warning, .error, .fault])
        #expect(entries.map(\.message) == ["d", "i", "n", "w", "e", "f"])
        #expect(entries.allSatisfy { $0.subsystem == "com.test" && $0.category == "Sample" })
    }
#endif

@Test
func channelWithoutStoreStillLogs() {
    // No store attached: should not crash, just emit to os.Logger.
    let channel = LogChannel(subsystem: "com.test", category: "NoStore")
    channel.error("no store attached")
}
