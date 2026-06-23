import LogKit
import os
import Testing

@Test
func levelsAreOrderedBySeverity() {
    #expect(LogLevel.debug < .info)
    #expect(LogLevel.info < .notice)
    #expect(LogLevel.notice < .error)
    #expect(LogLevel.error < .fault)
    #expect(LogLevel.allCases == [.debug, .info, .notice, .error, .fault])
}

@Test
func osLogTypeMapping() {
    #expect(LogLevel.debug.osLogType == .debug)
    #expect(LogLevel.info.osLogType == .info)
    #expect(LogLevel.notice.osLogType == .default)
    #expect(LogLevel.error.osLogType == .error)
    #expect(LogLevel.fault.osLogType == .fault)
}
