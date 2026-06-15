import Foundation

/// Reads/writes `ideas.md`. Each entry is delimited by a metadata HTML comment
/// so the file stays clean markdown:
///
///     # Ideas
///
///     <!-- id: a1b2c3d4 created: 2026-06-15T23:30 pinned: true -->
///     ## Pomodoro mode
///     A focus timer that pulls the top task and counts down its estimate.
///
///     <!-- id: 9f8e7d6c created: 2026-06-14T10:00 -->
///     ## Newsletter angle
///     ...
enum IdeasParser {
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func newID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    static func parse(content: String) -> [Idea] {
        let lines = content.components(separatedBy: "\n")
        var ideas: [Idea] = []

        var current: (id: String, created: Date, pinned: Bool)?
        var titleSet = false
        var title = ""
        var bodyLines: [String] = []

        func flush() {
            guard let meta = current else { return }
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            ideas.append(Idea(id: meta.id, title: title.trimmingCharacters(in: .whitespaces),
                              body: body, createdAt: meta.created, pinned: meta.pinned))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Strict shape so free-form body text (prose mentioning "id:", a
            // stray "<!-- TODO -->", etc.) is never mistaken for an entry header.
            if trimmed.hasPrefix("<!-- id:"), trimmed.hasSuffix("-->") {
                flush()
                current = parseMeta(trimmed)
                titleSet = false
                title = ""
                bodyLines = []
            } else if current != nil {
                if !titleSet, trimmed.hasPrefix("## ") {
                    title = String(trimmed.dropFirst(3))
                    titleSet = true
                } else {
                    bodyLines.append(unescapeBodyLine(line))
                }
            }
        }
        flush()
        return ideas
    }

    private static func parseMeta(_ comment: String) -> (id: String, created: Date, pinned: Bool) {
        let inner = comment
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
        // Tolerate both `key: value` and `key:value`. The created value
        // (yyyy-MM-dd'T'HH:mm) has no spaces, so it's always one token.
        let parts = inner.split(separator: " ").map(String.init)
        var dict: [String: String] = [:]
        var i = 0
        while i < parts.count {
            let p = parts[i]
            if p.hasSuffix(":") {
                let key = String(p.dropLast())
                if i + 1 < parts.count { dict[key] = parts[i + 1]; i += 2 } else { i += 1 }
            } else if let colon = p.firstIndex(of: ":") {
                dict[String(p[..<colon])] = String(p[p.index(after: colon)...])
                i += 1
            } else {
                i += 1
            }
        }
        return (
            id: dict["id"] ?? newID(),
            created: stamp.date(from: dict["created"] ?? "") ?? Date(timeIntervalSince1970: 0),
            pinned: dict["pinned"] == "true"
        )
    }

    static func serialize(_ ideas: [Idea]) -> String {
        var out = "# Ideas\n"
        for idea in ideas {
            out += "\n<!-- id: \(idea.id) created: \(stamp.string(from: idea.createdAt))"
            if idea.pinned { out += " pinned: true" }
            out += " -->\n"
            let title = idea.title.trimmingCharacters(in: .whitespaces)
            out += "## \(title.isEmpty ? "Untitled" : title)\n"
            let body = idea.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { out += escapeBody(body) + "\n" }
        }
        return out
    }

    // A body line that is itself a verbatim metadata comment would otherwise be
    // re-read as an entry header and split the idea. We break the match with a
    // zero-width space right after `<!--` on serialize and strip it on parse, so
    // the body round-trips byte-for-byte while never being mistaken for a header.
    private static let zwsp = "\u{200B}"

    private static func escapeBody(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: false).map { sub -> String in
            let line = String(sub)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("<!-- id:") {
                return line.replacingOccurrences(of: "<!--", with: "<!--\(zwsp)")
            }
            return line
        }.joined(separator: "\n")
    }

    private static func unescapeBodyLine(_ line: String) -> String {
        line.replacingOccurrences(of: "<!--\(zwsp)", with: "<!--")
    }
}
