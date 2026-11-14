#if DEBUG
    import AccessibilitySnapshotParser
    import SnapshotKit
    import SwiftUI
    import TestHostSupport
    import Testing
    @testable import WhereUI

    @MainActor
    @Suite(.serialized)
    struct DeviceLayoutLabViewTests {
        @Test func changingDeviceLayoutsKeepsSearchUntilAnExplicitReset() async throws {
            let model = WhereDemoWorldModel()
            await model.load()
            guard case let .loaded(world) = model.state else {
                Issue.record("Demo world did not load")
                return
            }
            let state = DeviceLayoutLabState(model: model)
            let host = UIHostingController(rootView: DeviceLayoutLabView(state: state)
                .whereBroadwayRoot())
            host.safeAreaRegions = []
            try await show(host) { controller in
                controller.view.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
                controller.view.window?.layer.speed = 1
                controller.view.layoutIfNeeded()
                try await waitForStage("Settings tab", in: controller.view) {
                    HostedAccessibility.objects(in: controller.view)
                        .contains { $0.accessibilityLabel == "Settings" }
                }
                let settings = try #require(HostedAccessibility.objects(in: controller.view)
                    .first { $0.accessibilityLabel == "Settings" })
                if let control = settings as? UIControl {
                    control.sendActions(for: .touchUpInside)
                } else {
                    try #require(settings.accessibilityActivate())
                }
                try await waitForStage("Settings search", in: controller.view) {
                    searchField(in: controller.view) != nil
                }
                let search = try #require(searchField(in: controller.view))
                search.text = "appearance"
                search.sendActions(for: .editingChanged)
                let devices = SnapshotConfiguration.DeviceProfile.allCases.flatMap { profile in
                    SnapshotConfiguration.DeviceProfile.Orientation.allCases.map {
                        DeviceLayoutConfiguration.device(profile, $0)
                    }
                }
                let configurations = devices + SnapshotConfiguration.DuoPose.allCases.map {
                    DeviceLayoutConfiguration.duo($0)
                }
                for configuration in configurations {
                    state.configuration = configuration
                    try await waitForStage(configuration.title, in: controller.view) {
                        AdaptivePaneTestSupport.descendants(
                            of: controller.view,
                            matching: UIView.self,
                        )
                        .contains {
                            // UIKit rounds synthetic bounds to the host display's pixel grid.
                            let pixel = 1 / controller.traitCollection.displayScale + 1e-9
                            return abs($0.bounds.width - configuration.size.width) <= pixel
                                && abs($0.bounds.height - configuration.size.height) <= pixel
                        }
                        && searchField(in: controller.view)?.text == "appearance"
                    }
                    #expect(state.model === model)
                    guard case let .loaded(current) = state.model.state else {
                        Issue.record("Changing a layout unloaded the demo")
                        return
                    }
                    #expect(current.report === world.report)
                }
                state.reset()
                try await waitForStage("Reset Demo", in: controller.view) {
                    guard case let .loaded(replacement) = state.model.state else { return false }
                    return replacement.report !== world.report
                        && HostedAccessibility.objects(in: controller.view).contains {
                            $0.accessibilityLabel == "Locations" && $0.accessibilityTraits
                                .contains(.selected)
                        }
                }
                #expect(state.configuration == configurations.last)
                #expect(state.model !== model)
            }
        }

        private func waitForStage(
            _ stage: String,
            in view: UIView,
            _ predicate: () -> Bool,
        ) async throws {
            do { try await waitForAsync(predicate: predicate) }
            catch {
                let labels = HostedAccessibility.objects(in: view).compactMap(\.accessibilityLabel)
                let sizes = Set(AdaptivePaneTestSupport.descendants(of: view, matching: UIView.self)
                    .map { "\($0.bounds.size)" })
                throw TestHostError(
                    "Lab stage \(stage): \(error); labels=\(labels); sizes=\(sizes); search=\(String(describing: searchField(in: view)?.text))",
                )
            }
        }

        private func searchField(in view: UIView) -> UISearchTextField? {
            AdaptivePaneTestSupport.descendants(of: view, matching: UISearchTextField.self)
                .first { field in
                    var ancestor: UIView? = field
                    while let current = ancestor {
                        if current.isHidden || current.alpha == 0 { return false }
                        ancestor = current.superview
                    }
                    return field.window != nil && field.bounds.width > 0
                }
        }
    }
#endif
