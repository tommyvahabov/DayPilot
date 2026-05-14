import Foundation

// MARK: - File paths
let HOME = NSHomeDirectory()
let TODOS_PATH = "\(HOME)/scheduler/todos.md"
let MEMORY_PATH = "\(HOME)/scheduler/memory.md"
let DONE_PATH = "\(HOME)/scheduler/done.md"
let SCHEDULER_DIR = "\(HOME)/scheduler"

func ensureDir() {
    try? FileManager.default.createDirectory(atPath: SCHEDULER_DIR, withIntermediateDirectories: true)
}

func readLines(_ path: String) -> [String] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return content.components(separatedBy: "\n")
}

func writeLines(_ lines: [String], to path: String) {
    try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
}

func isNoteLine(_ line: String) -> Bool {
    if line.isEmpty { return false }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let startsIndent = line.hasPrefix("  ") || line.hasPrefix("\t")
    return startsIndent && !trimmed.hasPrefix("- [ ] ") && !trimmed.hasPrefix("- [x] ")
}

func collectNotes(_ lines: [String], at idx: Int) -> [String] {
    var notes: [String] = []
    var j = idx + 1
    while j < lines.count && isNoteLine(lines[j]) {
        notes.append(lines[j].trimmingCharacters(in: .whitespaces))
        j += 1
    }
    return notes
}

func countNoteLines(_ lines: [String], at idx: Int) -> Int {
    var count = 0
    var j = idx + 1
    while j < lines.count && isNoteLine(lines[j]) {
        count += 1
        j += 1
    }
    return count
}

// MARK: - JSON helpers
func toJSON(_ obj: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
          let str = String(data: data, encoding: .utf8) else { return "null" }
    return str
}

func textContent(_ s: String) -> [String: Any] {
    return ["content": [["type": "text", "text": s]]]
}

// MARK: - Tool implementations
func toolListTasks() -> [String: Any] {
    let lines = readLines(TODOS_PATH)
    var tasks: [[String: Any]] = []
    var i = 0
    while i < lines.count {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") {
            let raw = String(trimmed.dropFirst(6))
            let notes = collectNotes(lines, at: i)
            tasks.append(["line": i, "status": "open", "raw": raw, "notes": notes])
            i += notes.count + 1
        } else if trimmed.hasPrefix("- [x] ") {
            let raw = String(trimmed.dropFirst(6))
            let notes = collectNotes(lines, at: i)
            tasks.append(["line": i, "status": "done", "raw": raw, "notes": notes])
            i += notes.count + 1
        } else {
            i += 1
        }
    }
    let json = toJSON(tasks)
    return textContent(json)
}

func toolAddTask(_ args: [String: Any]) -> [String: Any] {
    guard let title = args["title"] as? String, !title.isEmpty else {
        return textContent("Error: title is required")
    }
    ensureDir()
    var lines = readLines(TODOS_PATH)
    if lines.isEmpty { lines = ["# Todos", ""] }
    var task = "- [ ] \(title)"
    if let p = args["project"] as? String, !p.isEmpty { task += " | project: \(p)" }
    if let e = args["effort"] as? String, !e.isEmpty { task += " | effort: \(e)" }
    if let d = args["deadline"] as? String, !d.isEmpty { task += " | deadline: \(d)" }
    lines.append(task)
    var noteCount = 0
    if let notes = args["notes"] as? [String] {
        for n in notes {
            lines.append("  \(n)")
            noteCount += 1
        }
    }
    writeLines(lines, to: TODOS_PATH)
    return textContent("Added: \(task)" + (noteCount > 0 ? " (\(noteCount) notes)" : ""))
}

func findTaskIndex(_ lines: [String], titleSubstring: String, openOnly: Bool = false, doneOnly: Bool = false) -> Int? {
    let lower = titleSubstring.lowercased()
    for i in 0..<lines.count {
        let line = lines[i]
        let lowerLine = line.lowercased()
        let isOpen = line.contains("- [ ] ")
        let isDone = line.contains("- [x] ")
        if openOnly && !isOpen { continue }
        if doneOnly && !isDone { continue }
        if !openOnly && !doneOnly && !isOpen && !isDone { continue }
        if lowerLine.contains(lower) { return i }
    }
    return nil
}

func toolUpdateTaskNotes(_ args: [String: Any]) -> [String: Any] {
    guard let title = args["title"] as? String,
          let notes = args["notes"] as? [String] else {
        return textContent("Error: title and notes are required")
    }
    var lines = readLines(TODOS_PATH)
    guard let i = findTaskIndex(lines, titleSubstring: title) else {
        return textContent("No task matching \"\(title)\" found")
    }
    let oldCount = countNoteLines(lines, at: i)
    if oldCount > 0 {
        lines.removeSubrange((i + 1)..<(i + 1 + oldCount))
    }
    for (idx, n) in notes.enumerated() {
        lines.insert("  \(n)", at: i + 1 + idx)
    }
    writeLines(lines, to: TODOS_PATH)
    return textContent("Updated notes on: \(lines[i].trimmingCharacters(in: .whitespaces)) (\(notes.count) notes)")
}

func toolCompleteTask(_ args: [String: Any]) -> [String: Any] {
    guard let title = args["title"] as? String else {
        return textContent("Error: title is required")
    }
    var lines = readLines(TODOS_PATH)
    guard let i = findTaskIndex(lines, titleSubstring: title, openOnly: true) else {
        return textContent("No open task matching \"\(title)\" found")
    }
    let original = lines[i]
    lines[i] = original.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
    writeLines(lines, to: TODOS_PATH)
    let raw = original.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- [ ] ", with: "")
    logDone(raw)
    return textContent("Completed: \(lines[i].trimmingCharacters(in: .whitespaces))")
}

func toolUncompleteTask(_ args: [String: Any]) -> [String: Any] {
    guard let title = args["title"] as? String else {
        return textContent("Error: title is required")
    }
    var lines = readLines(TODOS_PATH)
    guard let i = findTaskIndex(lines, titleSubstring: title, doneOnly: true) else {
        return textContent("No completed task matching \"\(title)\" found")
    }
    lines[i] = lines[i].replacingOccurrences(of: "- [x] ", with: "- [ ] ")
    writeLines(lines, to: TODOS_PATH)
    return textContent("Reopened: \(lines[i].trimmingCharacters(in: .whitespaces))")
}

func toolRemoveTask(_ args: [String: Any]) -> [String: Any] {
    guard let title = args["title"] as? String else {
        return textContent("Error: title is required")
    }
    var lines = readLines(TODOS_PATH)
    guard let i = findTaskIndex(lines, titleSubstring: title) else {
        return textContent("No task matching \"\(title)\" found")
    }
    let noteCount = countNoteLines(lines, at: i)
    let removed = lines[i]
    lines.removeSubrange(i..<(i + 1 + noteCount))
    writeLines(lines, to: TODOS_PATH)
    return textContent("Removed: \(removed.trimmingCharacters(in: .whitespaces)) (+ \(noteCount) notes)")
}

func toolReadMemory() -> [String: Any] {
    guard let content = try? String(contentsOfFile: MEMORY_PATH, encoding: .utf8) else {
        return textContent("No memory.md found")
    }
    return textContent(content)
}

func toolReadDoneLog() -> [String: Any] {
    guard let content = try? String(contentsOfFile: DONE_PATH, encoding: .utf8) else {
        return textContent("No done.md found — no tasks completed yet")
    }
    return textContent(content)
}

func toolUpdateMemory(_ args: [String: Any]) -> [String: Any] {
    guard let content = args["content"] as? String else {
        return textContent("Error: content is required")
    }
    ensureDir()
    try? content.write(toFile: MEMORY_PATH, atomically: true, encoding: .utf8)
    return textContent("memory.md updated")
}

func toolSetCapacity(_ args: [String: Any]) -> [String: Any] {
    guard let capacity = args["capacity"] as? String else {
        return textContent("Error: capacity is required")
    }
    ensureDir()
    if !FileManager.default.fileExists(atPath: MEMORY_PATH) {
        let initial = "## Settings\ndaily_capacity: \(capacity)\n"
        try? initial.write(toFile: MEMORY_PATH, atomically: true, encoding: .utf8)
        return textContent("Set daily_capacity to \(capacity) (created memory.md)")
    }
    var lines = readLines(MEMORY_PATH)
    var found = false
    for i in 0..<lines.count {
        if lines[i].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("daily_capacity:") {
            lines[i] = "daily_capacity: \(capacity)"
            found = true
            break
        }
    }
    if !found {
        if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Settings" }) {
            lines.insert("daily_capacity: \(capacity)", at: header + 1)
        } else {
            lines.append("")
            lines.append("## Settings")
            lines.append("daily_capacity: \(capacity)")
        }
    }
    writeLines(lines, to: MEMORY_PATH)
    return textContent("daily_capacity set to \(capacity)")
}

func toolSetProject(_ args: [String: Any]) -> [String: Any] {
    guard let name = args["name"] as? String,
          let priority = args["priority"] as? Int else {
        return textContent("Error: name and priority are required")
    }
    ensureDir()
    var entry = "- \(name) | priority: \(priority)"
    if let deadline = args["deadline"] as? String, !deadline.isEmpty {
        entry += " | deadline: \(deadline)"
    }
    var lines = readLines(MEMORY_PATH)
    if lines.isEmpty { lines = [""] }
    let existing = lines.firstIndex(where: {
        let trimmed = $0.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- \(name) |") || trimmed == "- \(name)"
    })
    if let idx = existing {
        lines[idx] = entry
    } else if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Projects" }) {
        lines.insert(entry, at: header + 1)
    } else {
        lines.insert(entry, at: 0)
        lines.insert("## Projects", at: 0)
    }
    writeLines(lines, to: MEMORY_PATH)
    return textContent("Project \"\(name)\" set: priority \(priority)" + ((args["deadline"] as? String).map { ", deadline \($0)" } ?? ""))
}

// MARK: - done.md logging
func logDone(_ rawTask: String) {
    ensureDir()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let today = formatter.string(from: Date())
    let header = "## \(today)"
    var lines = readLines(DONE_PATH)
    let entry = "- [x] \(rawTask)"
    if let headerIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
        var insertAt = headerIdx + 1
        while insertAt < lines.count {
            let t = lines[insertAt].trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("## ") { break }
            insertAt += 1
        }
        lines.insert(entry, at: insertAt)
    } else {
        var insertAt = 0
        if !lines.isEmpty && lines[0].hasPrefix("# ") {
            insertAt = 1
            if insertAt < lines.count && lines[insertAt].isEmpty { insertAt = 2 }
        }
        lines.insert("", at: insertAt)
        lines.insert(entry, at: insertAt)
        lines.insert(header, at: insertAt)
    }
    writeLines(lines, to: DONE_PATH)
}

// MARK: - Tool registry
struct ToolSpec {
    let name: String
    let description: String
    let schema: [String: Any]
    let handler: ([String: Any]) -> [String: Any]
}

let tools: [ToolSpec] = [
    ToolSpec(
        name: "list_tasks",
        description: "List all tasks from ~/scheduler/todos.md (includes notes)",
        schema: ["type": "object", "properties": [:] as [String: Any]],
        handler: { _ in toolListTasks() }
    ),
    ToolSpec(
        name: "add_task",
        description: "Add a new task to ~/scheduler/todos.md. Fields: title (required), project, effort (e.g. '30m', '1h'), deadline (YYYY-MM-DD), notes (array of strings)",
        schema: [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "Task title"],
                "project": ["type": "string", "description": "Project name"],
                "effort": ["type": "string", "description": "Effort estimate, e.g. '30m', '1h', '1h30m'"],
                "deadline": ["type": "string", "description": "Deadline in YYYY-MM-DD format"],
                "notes": ["type": "array", "items": ["type": "string"], "description": "Task notes, each string is a line"],
            ],
            "required": ["title"],
        ],
        handler: toolAddTask
    ),
    ToolSpec(
        name: "update_task_notes",
        description: "Add or replace notes on a task (by title partial match)",
        schema: [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "Task title or partial match"],
                "notes": ["type": "array", "items": ["type": "string"], "description": "New notes (replaces existing)"],
            ],
            "required": ["title", "notes"],
        ],
        handler: toolUpdateTaskNotes
    ),
    ToolSpec(
        name: "complete_task",
        description: "Mark a task as done by its title (partial match). Also logs to ~/scheduler/done.md",
        schema: [
            "type": "object",
            "properties": ["title": ["type": "string", "description": "Task title or partial match"]],
            "required": ["title"],
        ],
        handler: toolCompleteTask
    ),
    ToolSpec(
        name: "uncomplete_task",
        description: "Mark a completed task as open again by its title (partial match)",
        schema: [
            "type": "object",
            "properties": ["title": ["type": "string", "description": "Task title or partial match"]],
            "required": ["title"],
        ],
        handler: toolUncompleteTask
    ),
    ToolSpec(
        name: "remove_task",
        description: "Remove a task and its notes entirely by title (partial match)",
        schema: [
            "type": "object",
            "properties": ["title": ["type": "string", "description": "Task title or partial match"]],
            "required": ["title"],
        ],
        handler: toolRemoveTask
    ),
    ToolSpec(
        name: "read_memory",
        description: "Read ~/scheduler/memory.md (projects, priorities, capacity)",
        schema: ["type": "object", "properties": [:] as [String: Any]],
        handler: { _ in toolReadMemory() }
    ),
    ToolSpec(
        name: "read_done_log",
        description: "Read ~/scheduler/done.md — daily log of completed tasks",
        schema: ["type": "object", "properties": [:] as [String: Any]],
        handler: { _ in toolReadDoneLog() }
    ),
    ToolSpec(
        name: "update_memory",
        description: "Write or overwrite ~/scheduler/memory.md with new content (projects, priorities, capacity, focus)",
        schema: [
            "type": "object",
            "properties": ["content": ["type": "string", "description": "Full markdown content for memory.md"]],
            "required": ["content"],
        ],
        handler: toolUpdateMemory
    ),
    ToolSpec(
        name: "set_capacity",
        description: "Update daily_capacity in memory.md without touching other sections",
        schema: [
            "type": "object",
            "properties": ["capacity": ["type": "string", "description": "New capacity, e.g. '4h', '6h', '2h30m'"]],
            "required": ["capacity"],
        ],
        handler: toolSetCapacity
    ),
    ToolSpec(
        name: "set_project",
        description: "Add or update a project in memory.md",
        schema: [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Project name"],
                "priority": ["type": "number", "description": "Priority (1 = highest)"],
                "deadline": ["type": "string", "description": "Deadline in YYYY-MM-DD format"],
            ],
            "required": ["name", "priority"],
        ],
        handler: toolSetProject
    ),
]

// MARK: - JSON-RPC handling
func sendResponse(_ id: Any?, result: [String: Any]) {
    var msg: [String: Any] = ["jsonrpc": "2.0", "result": result]
    if let id = id { msg["id"] = id }
    let json = toJSON(msg)
    FileHandle.standardOutput.write(Data((json + "\n").utf8))
}

func sendError(_ id: Any?, code: Int, message: String) {
    var msg: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
    if let id = id { msg["id"] = id }
    let json = toJSON(msg)
    FileHandle.standardOutput.write(Data((json + "\n").utf8))
}

func handleMessage(_ msg: [String: Any]) {
    let id = msg["id"]
    guard let method = msg["method"] as? String else { return }
    let params = (msg["params"] as? [String: Any]) ?? [:]

    switch method {
    case "initialize":
        sendResponse(id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "daypilot", "version": "1.0.0"],
        ])
    case "notifications/initialized":
        return
    case "tools/list":
        let list = tools.map { tool -> [String: Any] in
            return [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": tool.schema,
            ]
        }
        sendResponse(id, result: ["tools": list])
    case "tools/call":
        guard let name = params["name"] as? String else {
            sendError(id, code: -32602, message: "Missing tool name")
            return
        }
        let args = (params["arguments"] as? [String: Any]) ?? [:]
        guard let tool = tools.first(where: { $0.name == name }) else {
            sendError(id, code: -32601, message: "Unknown tool: \(name)")
            return
        }
        let result = tool.handler(args)
        sendResponse(id, result: result)
    default:
        if id != nil {
            sendError(id, code: -32601, message: "Method not found: \(method)")
        }
    }
}

// MARK: - Main loop (NDJSON over stdin/stdout)
while let line = readLine() {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    guard let data = trimmed.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        continue
    }
    handleMessage(json)
}
