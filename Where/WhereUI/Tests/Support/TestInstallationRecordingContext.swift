@_spi(Testing) import WhereCore
@_spi(Testing) import WhereUI

@MainActor
func makeInstallationRecordingContextStore(
    context: InstallationRecordingContext = .testing,
) -> InMemoryInstallationRecordingContextStore {
    InMemoryInstallationRecordingContextStore(context: context)
}

@MainActor
func makeInstallationRecordingContextStore(
    setup: InstallationRecordingContext.SetupCompletion,
) -> InMemoryInstallationRecordingContextStore {
    let context = InstallationRecordingContext.testing
    return InMemoryInstallationRecordingContextStore(context: InstallationRecordingContext(
        currentDevice: context.currentDevice,
        registeredAt: context.registeredAt,
        recordingChoice: .on(enabledAt: context.registeredAt, setup: setup),
        isRejoining: false,
    ))
}
