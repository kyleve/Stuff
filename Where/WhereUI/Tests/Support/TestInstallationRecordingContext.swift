@_spi(Testing) import WhereCore
@_spi(Testing) import WhereUI

@MainActor
func makeInstallationRecordingContextStore(
    context: InstallationRecordingContext = .testing,
) -> InMemoryInstallationRecordingContextStore {
    InMemoryInstallationRecordingContextStore(context: context)
}
