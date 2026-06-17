import Darwin
import Dispatch
import Foundation

/// Watches a single file for writes and fires a debounced callback. Re-arms on
/// every change so it keeps following the path across atomic replaces (the
/// extractor writes graph.json to a temp file and renames it into place, which
/// swaps the inode the watched descriptor points at).
final class FileWatcher {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.stuff.codegraph.viewer.filewatch")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var pending: DispatchWorkItem?

    init(url: URL, debounce: TimeInterval, onChange: @escaping () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in self?.arm() }
    }

    func stop() {
        queue.async { [weak self] in
            self?.pending?.cancel()
            self?.source?.cancel()
            self?.source = nil
        }
    }

    private func arm() {
        source?.cancel()
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: queue,
        )
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.setCancelHandler { [fileDescriptor] in close(fileDescriptor) }
        self.source = source
        source.resume()
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            arm()
            onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit {
        source?.cancel()
    }
}
