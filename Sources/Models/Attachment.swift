import Foundation

/// A file attached to a task. Persisted as part of the task line's `attach:`
/// token (paths separated by `; `), with the bytes living under
/// `~/scheduler/attachments/`. The relative path is the source of truth; the
/// filename shown to the user strips the collision-avoidance id prefix.
struct Attachment: Identifiable, Equatable, Hashable {
    /// Path relative to `~/scheduler`, e.g. `attachments/ab12cd34-error.png`.
    let relativePath: String

    var id: String { relativePath }

    /// On-disk basename, e.g. `ab12cd34-error.png`.
    var storedName: String { (relativePath as NSString).lastPathComponent }

    /// Display name with the 8-char id prefix stripped, e.g. `error.png`.
    var displayName: String {
        let name = storedName
        guard let dash = name.firstIndex(of: "-"),
              name.distance(from: name.startIndex, to: dash) == 8 else { return name }
        return String(name[name.index(after: dash)...])
    }

    var ext: String { (storedName as NSString).pathExtension.lowercased() }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "tiff", "tif"].contains(ext)
    }

    /// SF Symbol used when no thumbnail is available.
    var icon: String {
        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx", "pages", "rtf", "txt", "md": return "doc.text"
        case "xls", "xlsx", "numbers", "csv": return "tablecells"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle"
        case "zip", "tar", "gz", "dmg": return "doc.zipper"
        case "mp4", "mov", "m4v", "avi": return "film"
        case "mp3", "wav", "m4a", "aiff": return "waveform"
        default: return isImage ? "photo" : "doc"
        }
    }
}
