import Darwin
import Dispatch
import Foundation

/// Watches an index store's `units` directory and fires a debounced callback
/// whenever a build writes new index data into it.
final class DataStoreWatcher {
    private let directory: String
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.stuff.code-graph-extract.watch")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var pending: DispatchWorkItem?

    init(directory: String, debounce: TimeInterval, onChange: @escaping () -> Void) {
        self.directory = directory
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() throws {
        fileDescriptor = open(directory, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            throw ExtractError.indexStoreNotFound(directory)
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue,
        )
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.setCancelHandler { [fileDescriptor] in close(fileDescriptor) }
        self.source = source
        source.resume()
    }

    /// Hand the process over to GCD so the watch keeps running. Never returns;
    /// the process ends on interrupt (ctrl-C).
    func wait() -> Never {
        dispatchMain()
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
