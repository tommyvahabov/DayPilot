import Foundation

/// Watches individual files for content changes using DispatchSource per file.
///
/// Survives atomic writes. Both this app and the MCP server save with
/// `write(toFile:atomically:true)`, which writes a temp file and `rename()`s it
/// over the original — replacing the file's *inode*. A naive per-file watch is
/// bound to the original inode, so after the first atomic save it watches a dead,
/// unlinked inode and never fires again. That made the app go blind to external
/// (MCP) edits and clobber them on its next `writeBack()`. We fix it by re-arming:
/// on a `.delete`/`.rename` event the fd is stale, so we cancel it and re-`open()`
/// the path to watch the new inode. Plain in-place writes still fire via
/// `.write`/`.extend` on the live inode, so both write styles are covered.
final class FileWatcher {
    private let onChange: () -> Void
    private let debounceInterval: TimeInterval = 0.25
    private let queue = DispatchQueue.global(qos: .utility)
    private let lock = NSLock()
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var debounceWorkItem: DispatchWorkItem?

    /// Retained only for source compatibility with existing call sites. The old
    /// "swallow the next event" scheme is gone: it dropped legitimate external
    /// edits whenever the flag was left set, which silently lost MCP-added tasks.
    /// A self-write now simply triggers a harmless reload of the app's own content.
    var isSelfEditing: Bool = false

    init?(filePaths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange
        for path in filePaths { arm(path) }
        guard !sources.isEmpty else { return nil }
    }

    /// Open `path` and start a fresh watch on its current inode, replacing any
    /// existing (possibly dead) source for that path.
    private func arm(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Read the firing source's accumulated events via the stored handle
            // (avoids capturing `source` in its own handler).
            let flags: DispatchSource.FileSystemEvent = self.lock.withLock {
                self.sources[path]?.data ?? []
            }
            // Atomic replace unlinked the inode this fd points at — re-open the
            // path so we keep watching the file that now lives there.
            if flags.contains(.delete) || flags.contains(.rename) {
                self.queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.arm(path)
                }
            }
            self.scheduleChange()
        }
        source.setCancelHandler { close(fd) }

        lock.withLock {
            sources[path]?.cancel()   // tear down the prior (stale) watch, if any
            sources[path] = source
        }
        source.resume()
    }

    private func scheduleChange() {
        lock.withLock {
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange() }
            debounceWorkItem = work
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
        }
    }

    deinit {
        lock.withLock {
            for (_, source) in sources { source.cancel() }
        }
    }
}
