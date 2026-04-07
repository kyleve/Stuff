import SwiftUI
import UserNotifications
import WhereData
import WhereUI

@main
struct WhereApp: App {
    private let dataStore: WhereDataStore
    private let trackingController: BackgroundTrackingController
    private let appRefreshCoordinator: AppRefreshCoordinator
    @State private var viewModel: RootViewModel
    @State private var manualEntryViewModel: ManualEntryViewModel

    init() {
        let dataStore = WhereDataStore.makeDefault()
        let trackingStateController = TrackingStateController(store: dataStore.trackingStateStore)
        let locationBridge = AppleLocationBridge()
        let trackingController = BackgroundTrackingController(
            locationRepository: dataStore.locationRepository,
            authorizationProvider: locationBridge,
            wakeSource: locationBridge,
            jurisdictionResolver: AppleJurisdictionResolver(),
            notificationScheduler: AppleNotificationScheduler(),
            trackingStateController: trackingStateController,
        )
        let appRefreshCoordinator = AppRefreshCoordinator(trackingController: trackingController)
        locationBridge.attach(trackingController: trackingController)

        self.dataStore = dataStore
        self.trackingController = trackingController
        self.appRefreshCoordinator = appRefreshCoordinator
        _viewModel = State(
            initialValue: RootViewModel(
                provider: dataStore.makeYearProgressController(),
            ),
        )
        _manualEntryViewModel = State(
            initialValue: ManualEntryViewModel(
                manager: dataStore.manualEntryController,
                importer: dataStore.manualDataImportController,
                exporter: dataStore.yearExportController,
                yearDataProvider: dataStore.yearDataProvider,
                resetter: dataStore.resetController,
            ),
        )

        appRefreshCoordinator.register()
        appRefreshCoordinator.schedule()
        requestNotificationAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                viewModel: viewModel,
                manualEntryViewModel: manualEntryViewModel,
            )
            .task {
                await trackingController.prepareForLaunch()
            }
        }
    }

    private func requestNotificationAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound],
            )
        }
    }
}
