@_spi(Testing) import ForemanCore
import Foundation
import Testing

@MainActor
struct AppSettingsTests {
    @MainActor
    private final class ChangeRecorder {
        var changes: [AppSettings.Change] = []
    }

    private func makeSettings(
        scanDirectory: URL? = nil,
        agentExecutable: URL? = nil,
    ) -> (AppSettings, ChangeRecorder) {
        let recorder = ChangeRecorder()
        let settings = AppSettings(
            scanDirectory: scanDirectory,
            agentExecutable: agentExecutable,
        ) { recorder.changes.append($0) }
        return (settings, recorder)
    }

    @Test func resolvedScanDirectoryDefaultsToDevelopment() {
        let (settings, _) = makeSettings()

        #expect(settings.resolvedScanDirectory.lastPathComponent == "Development")

        settings.scanDirectory = URL(fileURLWithPath: "/tmp/repos")
        #expect(settings.resolvedScanDirectory.path == "/tmp/repos")
    }

    @Test func changesReportTheChangedProperty() {
        let (settings, recorder) = makeSettings()

        settings.scanDirectory = URL(fileURLWithPath: "/tmp/repos")
        settings.agentExecutable = URL(fileURLWithPath: "/usr/local/bin/cursor-agent")

        #expect(recorder.changes == [.scanDirectory, .agentExecutable])
    }

    @Test func sameValueReassignmentIsANoOp() {
        let url = URL(fileURLWithPath: "/tmp/repos")
        let (settings, recorder) = makeSettings(scanDirectory: url)

        settings.scanDirectory = url

        #expect(recorder.changes.isEmpty)
    }

    @Test func initialValuesDoNotNotify() {
        let (_, recorder) = makeSettings(
            scanDirectory: URL(fileURLWithPath: "/tmp/repos"),
            agentExecutable: URL(fileURLWithPath: "/usr/local/bin/cursor-agent"),
        )

        #expect(recorder.changes.isEmpty)
    }
}
