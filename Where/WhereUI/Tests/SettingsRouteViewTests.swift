import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

/// Exercises every typed Settings push through the production route renderer,
/// including heterogeneous values pushed by child destinations.
@MainActor
@Suite(.serialized)
struct SettingsRouteViewTests {
    @Test(arguments: SettingsDestination.allCases.filter { !$0.isSheet })
    func everyPushDestinationHosts(_ destination: SettingsDestination) throws {
        let world = try World()
        let rootView = world.host(route: SettingsRoute(destination))

        try show(UIHostingController(rootView: rootView)) { hosted in
            try waitFor {
                hosted.viewIfLoaded?.window != nil
                    && navigationController(in: hosted)?.viewControllers.count == 2
            }
        }
    }

    @Test func shareEvidenceArchivePushesASecondHeterogeneousRoute() throws {
        let world = try World()
        let rootView = world.host(
            route: SettingsRoute(.shareEvidence),
            nested: ShareEvidenceFeaturesView.Route.archive,
        )

        try show(UIHostingController(rootView: rootView)) { hosted in
            try waitFor {
                hosted.viewIfLoaded?.window != nil
                    && navigationController(in: hosted)?.viewControllers.count == 3
            }
        }
    }

    @Test func attachmentDetailPushesASecondHeterogeneousValue() throws {
        let evidence = try #require(PreviewSupport.sampleEvidence().first)
        let world = try World()
        let rootView = world.host(
            route: SettingsRoute(.attachments),
            nested: evidence,
        )

        try show(UIHostingController(rootView: rootView)) { hosted in
            try waitFor {
                hosted.viewIfLoaded?.window != nil
                    && navigationController(in: hosted)?.viewControllers.count == 3
            }
        }
    }

    private func navigationController(
        in viewController: UIViewController,
    ) -> UINavigationController? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        for child in viewController.children {
            if let navigationController = navigationController(in: child) {
                return navigationController
            }
        }
        return nil
    }
}

@MainActor
private struct World {
    let model: WhereModel
    let session: WhereSession
    let report: YearReportModel
    let backup: BackupModel
    let reminders: RemindersSettingsModel

    init() throws {
        let model = PreviewSupport.loadedModel()
        let session = try #require(
            model.session,
            "PreviewSupport.loadedModel() should create its session.",
        )

        self.model = model
        self.session = session
        report = YearReportModel(
            services: session.services,
            details: model.initialYearDetails,
            selectedYear: model.initialSelectedYear,
            preferences: session.preferences,
            now: session.now,
        )
        backup = BackupModel(services: session.services)
        reminders = RemindersSettingsModel(
            services: session.services,
            preferences: session.preferences,
            now: session.now,
        )
    }

    func host(route: SettingsRoute) -> some View {
        NavigationHost(
            route: route,
            report: report,
            backup: backup,
            reminders: reminders,
        )
        .environment(model)
        .environment(session)
    }

    func host(route: SettingsRoute, nested: some Hashable) -> some View {
        NavigationHost(
            route: route,
            nested: nested,
            report: report,
            backup: backup,
            reminders: reminders,
        )
        .environment(model)
        .environment(session)
    }
}

@MainActor
private struct NavigationHost: View {
    let report: YearReportModel
    let backup: BackupModel
    let reminders: RemindersSettingsModel

    @State private var path: NavigationPath

    init(
        route: SettingsRoute,
        report: YearReportModel,
        backup: BackupModel,
        reminders: RemindersSettingsModel,
    ) {
        var path = NavigationPath()
        path.append(route)
        self.init(
            path: path,
            report: report,
            backup: backup,
            reminders: reminders,
        )
    }

    init(
        route: SettingsRoute,
        nested: some Hashable,
        report: YearReportModel,
        backup: BackupModel,
        reminders: RemindersSettingsModel,
    ) {
        var path = NavigationPath()
        path.append(route)
        path.append(nested)
        self.init(
            path: path,
            report: report,
            backup: backup,
            reminders: reminders,
        )
    }

    private init(
        path: NavigationPath,
        report: YearReportModel,
        backup: BackupModel,
        reminders: RemindersSettingsModel,
    ) {
        _path = State(initialValue: path)
        self.report = report
        self.backup = backup
        self.reminders = reminders
    }

    var body: some View {
        NavigationStack(path: $path) {
            Color.clear
                .navigationDestination(for: SettingsRoute.self) { route in
                    SettingsRouteView(
                        route: route,
                        report: report,
                        backup: backup,
                        reminders: reminders,
                    )
                }
        }
    }
}
