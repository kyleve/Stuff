import InstallerKit

/// Keeps manual checks alive across redraws while letting the page cancel them on disappearance.
@MainActor
final class UpdatePageRefresh {
    private var task: Task<Void, Never>?

    @discardableResult
    func start(model: UpdateModel) -> Task<Void, Never> {
        task?.cancel()
        let task = Task { await model.refresh(force: true) }
        self.task = task
        return task
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
