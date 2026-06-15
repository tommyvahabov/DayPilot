import Foundation
import AppKit

/// Copies attached files into `~/scheduler/attachments/` and resolves them back
/// for display/opening. The app is unsandboxed, so plain file ops are enough —
/// no security-scoped bookmarks. Filenames get an 8-char id prefix so two
/// `screenshot.png` attachments never collide.
enum AttachmentService {
    static var schedulerDir: String { NSHomeDirectory() + "/scheduler" }
    static var attachmentsDir: String { schedulerDir + "/attachments" }

    /// Copy a file into the attachments store; returns the new `Attachment`
    /// (path relative to `~/scheduler`) or nil on failure.
    static func importFile(from source: URL) -> Attachment? {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: attachmentsDir, withIntermediateDirectories: true)

        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let stored = "\(id)-\(sanitize(source.lastPathComponent))"
        let dest = URL(fileURLWithPath: attachmentsDir).appendingPathComponent(stored)

        let needsStop = source.startAccessingSecurityScopedResource()
        defer { if needsStop { source.stopAccessingSecurityScopedResource() } }
        do {
            try fm.copyItem(at: source, to: dest)
        } catch {
            // Fall back to a byte copy if copyItem trips over metadata.
            guard let data = try? Data(contentsOf: source),
                  (try? data.write(to: dest)) != nil else { return nil }
        }
        return Attachment(relativePath: "attachments/\(stored)")
    }

    /// Write raw image data (e.g. a pasteboard paste) as a PNG attachment.
    static func importImageData(_ data: Data, suggestedName: String = "pasted-image.png") -> Attachment? {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: attachmentsDir, withIntermediateDirectories: true)
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let stored = "\(id)-\(sanitize(suggestedName))"
        let dest = URL(fileURLWithPath: attachmentsDir).appendingPathComponent(stored)
        guard (try? data.write(to: dest)) != nil else { return nil }
        return Attachment(relativePath: "attachments/\(stored)")
    }

    static func absoluteURL(for attachment: Attachment) -> URL {
        URL(fileURLWithPath: schedulerDir).appendingPathComponent(attachment.relativePath)
    }

    static func exists(_ attachment: Attachment) -> Bool {
        FileManager.default.fileExists(atPath: absoluteURL(for: attachment).path)
    }

    @discardableResult
    static func open(_ attachment: Attachment) -> Bool {
        let url = absoluteURL(for: attachment)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ attachment: Attachment) {
        NSWorkspace.shared.activateFileViewerSelecting([absoluteURL(for: attachment)])
    }

    /// Best-effort delete of the backing file. The markdown token is the source
    /// of truth, so a failed delete just leaves a harmless orphan.
    static func deleteFile(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: absoluteURL(for: attachment))
    }

    /// Thumbnail for image attachments; nil for everything else (callers fall
    /// back to `attachment.icon`). Downscaled so large screenshots stay cheap.
    static func thumbnail(for attachment: Attachment, max side: CGFloat = 320) -> NSImage? {
        guard attachment.isImage else { return nil }
        let url = absoluteURL(for: attachment)
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, side / max(size.width, size.height))
        if scale >= 1 { return image }
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1)
        thumb.unlockFocus()
        return thumb
    }

    /// Workspace icon for non-image files (or images missing from disk).
    static func fileIcon(for attachment: Attachment) -> NSImage {
        NSWorkspace.shared.icon(forFile: absoluteURL(for: attachment).path)
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._")
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return trimmed.isEmpty ? "file" : String(trimmed.prefix(80))
    }
}
