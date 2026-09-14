#if DEBUG && canImport(UIKit)
    import PortholeCore
    import SwiftUI

    /// Both readiness hooks and the rendered view use this same bounded coverage page.
    @MainActor
    final class PortholeCoverageSnapshotFixture {
        let model: PortholeCoverageModel
        private let module: PortholeCoverageModuleSummary?
        private let services: PortholeCoverageSnapshotServices
        private var preparation: Task<Void, Never>?

        init(module: PortholeCoverageModuleSummary?) {
            let services = PortholeCoverageSnapshotServices()
            self.services = services
            self.module = module
            model = PortholeCoverageModel(
                scope: PortholeCoverageSnapshotServices.scope,
                module: module?.module,
                execute: services.invoke,
            )
        }

        var content: some View {
            PortholeCoverageView(
                model: model,
                module: module,
                capabilities: [PortholeCoverageSnapshotServices.callable],
                objects: [],
                navigation: .init(reader: services, execute: services.invoke),
            )
        }

        func prepare() async {
            if let preparation { await preparation.value; return }
            let preparation = Task { [model] in
                await model.load()
                guard case .loaded = model.state else {
                    preconditionFailure("The coverage snapshot fixture did not load its page.")
                }
            }
            self.preparation = preparation
            await preparation.value
        }
    }
#endif
