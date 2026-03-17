import Foundation

/// Watches individual files for content changes using DispatchSource per file.
/// Uses a lock to protect mutable state accessed from multiple threads.
final class FileWatcher {
    private let onChange: () -> Void
    private let debounceInterval: TimeInterval = 0.5
    private let lock = NSLock()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var debounceWorkItem: DispatchWorkItem?
    private var _isSelfEditing = false

    var isSelfEditing: Bool {
        get { lock.withLock { _isSelfEditing } }
        set { lock.withLock { _isSelfEditing = newValue } }
    }

    init?(filePaths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange

        for path in filePaths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: DispatchQueue.global(qos: .utility)
            )
            sources.append(source)

            source.setEventHandler { [weak self] in
                guard let self else { return }
                if self.isSelfEditing {
                    self.isSelfEditing = false
                    return
                }
                self.lock.withLock {
                    self.debounceWorkItem?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        self?.onChange()
                    }
                    self.debounceWorkItem = work
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + self.debounceInterval, execute: work
                    )
                }
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
        }

        guard !sources.isEmpty else { return nil }
    }

    deinit {
        for source in sources {
            source.cancel()
        }
    }
}
