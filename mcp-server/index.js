import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { randomUUID } from "node:crypto";

const TODOS_PATH = join(homedir(), "scheduler", "todos.md");
const MEMORY_PATH = join(homedir(), "scheduler", "memory.md");
const DONE_PATH = join(homedir(), "scheduler", "done.md");
const IDEAS_PATH = join(homedir(), "scheduler", "ideas.md");

// Drop the noisy collab: tracking uuid so task lists stay readable.
function cleanRaw(raw) {
  return raw
    .split("|")
    .map((s) => s.trim())
    .filter((s) => !s.toLowerCase().startsWith("collab:"))
    .join(" | ");
}

function ensureDir() {
  const dir = join(homedir(), "scheduler");
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function readLines() {
  ensureDir();
  if (!existsSync(TODOS_PATH)) return ["# Todos", ""];
  return readFileSync(TODOS_PATH, "utf-8").split("\n");
}

function writeLines(lines) {
  writeFileSync(TODOS_PATH, lines.join("\n"), "utf-8");
}

function isNoteLine(line) {
  return line && (line.startsWith("  ") || line.startsWith("\t")) && !line.trim().startsWith("- [ ] ") && !line.trim().startsWith("- [x] ");
}

// Collect note lines following a task at index i
function collectNotes(lines, taskIdx) {
  const notes = [];
  let j = taskIdx + 1;
  while (j < lines.length && isNoteLine(lines[j])) {
    notes.push(lines[j].trim());
    j++;
  }
  return notes;
}

// Count note lines following a task at index i
function countNoteLines(lines, taskIdx) {
  let count = 0;
  let j = taskIdx + 1;
  while (j < lines.length && isNoteLine(lines[j])) {
    count++;
    j++;
  }
  return count;
}

const server = new McpServer({
  name: "daypilot",
  version: "1.1.0",
});

// Lean overview by default: open (+ proposed) tasks only, one compact line each
// with note counts (not bodies). Done tasks hidden; full context via get_task.
server.tool(
  "list_tasks",
  "Lean overview of tasks from ~/scheduler/todos.md: open (and proposed) tasks, one compact line each with note counts (not bodies). Done tasks hidden by default. Use get_task for a task's full notes/context. Options: include_done (bool), include_notes (bool).",
  {
    include_done: z.boolean().optional().describe("Also list completed tasks (default false)"),
    include_notes: z.boolean().optional().describe("Inline each task's note bodies (default false — counts only)"),
  },
  ({ include_done, include_notes }) => {
    const lines = readLines();
    const open = [], proposed = [], done = [];
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      let bucket = null, prefix = null;
      if (t.startsWith("- [ ] ")) { bucket = open; prefix = "- [ ] "; }
      else if (t.startsWith("- [?] ")) { bucket = proposed; prefix = "- [?] "; }
      else if (t.startsWith("- [x] ")) { bucket = done; prefix = "- [x] "; }
      if (bucket) {
        const notes = collectNotes(lines, i);
        bucket.push({ raw: cleanRaw(t.slice(prefix.length)), notes });
        i += notes.length;
      }
    }
    let out = "";
    const render = (heading, items) => {
      out += `${heading} (${items.length}):\n`;
      if (items.length === 0) out += "  (none)\n";
      for (const { raw, notes } of items) {
        out += `- ${raw}`;
        if (notes.length) out += `  [${notes.length} note${notes.length === 1 ? "" : "s"}]`;
        out += "\n";
        if (include_notes) for (const n of notes) out += `    ${n}\n`;
      }
    };
    render("Open", open);
    if (proposed.length) render("Proposed (awaiting human review)", proposed);
    if (include_done) render("Done", done);
    else if (done.length) out += `(${done.length} done hidden — pass include_done:true to show)\n`;
    if (!include_notes) out += "Use get_task(title) for a task's full notes/context.\n";
    return { content: [{ type: "text", text: out }] };
  }
);

// Full detail of one task on demand (title + all notes/context).
server.tool(
  "get_task",
  "Full detail of one task (by title partial match), including all its notes/context. Use after list_tasks when you need a specific task's context.",
  { title: z.string().describe("Task title or partial match") },
  ({ title }) => {
    const lines = readLines();
    const lower = title.toLowerCase();
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      const isTask = t.startsWith("- [ ] ") || t.startsWith("- [x] ") || t.startsWith("- [?] ");
      if (isTask && t.toLowerCase().includes(lower)) {
        const notes = collectNotes(lines, i);
        let out = `${cleanRaw(t)}\n`;
        if (notes.length === 0) out += "(no notes)\n";
        else { out += "notes:\n"; for (const n of notes) out += `  - ${n}\n`; }
        return { content: [{ type: "text", text: out }] };
      }
    }
    return { content: [{ type: "text", text: `No task matching "${title}" found` }] };
  }
);

// Add a task (with optional notes)
server.tool(
  "add_task",
  "Add a new task to ~/scheduler/todos.md. Fields: title (required), project, effort (e.g. '30m', '1h'), deadline (YYYY-MM-DD), notes (array of strings)",
  {
    title: z.string().describe("Task title"),
    project: z.string().optional().describe("Project name"),
    effort: z.string().optional().describe("Effort estimate, e.g. '30m', '1h', '1h30m'"),
    deadline: z.string().optional().describe("Deadline in YYYY-MM-DD format"),
    notes: z.array(z.string()).optional().describe("Task notes, each string is a line"),
  },
  ({ title, project, effort, deadline, notes }) => {
    const lines = readLines();
    let task = `- [ ] ${title}`;
    if (project) task += ` | project: ${project}`;
    if (effort) task += ` | effort: ${effort}`;
    if (deadline) task += ` | deadline: ${deadline}`;
    lines.push(task);
    if (notes && notes.length > 0) {
      for (const note of notes) {
        lines.push(`  ${note}`);
      }
    }
    writeLines(lines);
    return { content: [{ type: "text", text: `Added: ${task}${notes ? ` (${notes.length} notes)` : ""}` }] };
  }
);

// Add/update notes on a task
server.tool(
  "update_task_notes",
  "Add or replace notes on a task (by title partial match)",
  {
    title: z.string().describe("Task title or partial match"),
    notes: z.array(z.string()).describe("New notes (replaces existing)"),
  },
  ({ title, notes }) => {
    const lines = readLines();
    const lower = title.toLowerCase();
    for (let i = 0; i < lines.length; i++) {
      if ((lines[i].includes("- [ ] ") || lines[i].includes("- [x] ")) && lines[i].toLowerCase().includes(lower)) {
        // Remove old notes
        const oldCount = countNoteLines(lines, i);
        lines.splice(i + 1, oldCount);
        // Insert new notes
        for (let n = notes.length - 1; n >= 0; n--) {
          lines.splice(i + 1, 0, `  ${notes[n]}`);
        }
        writeLines(lines);
        return { content: [{ type: "text", text: `Updated notes on: ${lines[i].trim()} (${notes.length} notes)` }] };
      }
    }
    return { content: [{ type: "text", text: `No task matching "${title}" found` }] };
  }
);

// Complete a task
server.tool(
  "complete_task",
  "Mark a task as done by its title (partial match). Also logs to ~/scheduler/done.md",
  {
    title: z.string().describe("Task title or partial match"),
  },
  ({ title }) => {
    const lines = readLines();
    const lower = title.toLowerCase();
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes("- [ ] ") && lines[i].toLowerCase().includes(lower)) {
        const taskLine = lines[i];
        lines[i] = lines[i].replace("- [ ] ", "- [x] ");
        writeLines(lines);
        logDone(taskLine.trim().replace("- [ ] ", ""));
        return { content: [{ type: "text", text: `Completed: ${lines[i].trim()}` }] };
      }
    }
    return { content: [{ type: "text", text: `No open task matching "${title}" found` }] };
  }
);

// Uncomplete a task
server.tool(
  "uncomplete_task",
  "Mark a completed task as open again by its title (partial match)",
  {
    title: z.string().describe("Task title or partial match"),
  },
  ({ title }) => {
    const lines = readLines();
    const lower = title.toLowerCase();
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes("- [x] ") && lines[i].toLowerCase().includes(lower)) {
        lines[i] = lines[i].replace("- [x] ", "- [ ] ");
        writeLines(lines);
        return { content: [{ type: "text", text: `Reopened: ${lines[i].trim()}` }] };
      }
    }
    return { content: [{ type: "text", text: `No completed task matching "${title}" found` }] };
  }
);

// Remove a task (and its notes)
server.tool(
  "remove_task",
  "Remove a task and its notes entirely by title (partial match)",
  {
    title: z.string().describe("Task title or partial match"),
  },
  ({ title }) => {
    const lines = readLines();
    const lower = title.toLowerCase();
    for (let i = 0; i < lines.length; i++) {
      if ((lines[i].includes("- [ ] ") || lines[i].includes("- [x] ")) && lines[i].toLowerCase().includes(lower)) {
        const noteCount = countNoteLines(lines, i);
        const removed = lines.splice(i, 1 + noteCount);
        writeLines(lines);
        return { content: [{ type: "text", text: `Removed: ${removed[0].trim()} (+ ${noteCount} notes)` }] };
      }
    }
    return { content: [{ type: "text", text: `No task matching "${title}" found` }] };
  }
);

// Read memory.md
server.tool("read_memory", "Read ~/scheduler/memory.md (projects, priorities, capacity)", {}, () => {
  if (!existsSync(MEMORY_PATH)) {
    return { content: [{ type: "text", text: "No memory.md found" }] };
  }
  const content = readFileSync(MEMORY_PATH, "utf-8");
  return { content: [{ type: "text", text: content }] };
});

// Read done.md (daily completion log)
server.tool("read_done_log", "Read ~/scheduler/done.md — daily log of completed tasks", {}, () => {
  if (!existsSync(DONE_PATH)) {
    return { content: [{ type: "text", text: "No done.md found — no tasks completed yet" }] };
  }
  const content = readFileSync(DONE_PATH, "utf-8");
  return { content: [{ type: "text", text: content }] };
});

// Update memory.md
server.tool(
  "update_memory",
  "Write or overwrite ~/scheduler/memory.md with new content (projects, priorities, capacity, focus)",
  {
    content: z.string().describe("Full markdown content for memory.md"),
  },
  ({ content }) => {
    ensureDir();
    writeFileSync(MEMORY_PATH, content, "utf-8");
    return { content: [{ type: "text", text: "memory.md updated" }] };
  }
);

// Set daily capacity
server.tool(
  "set_capacity",
  "Update daily_capacity in memory.md without touching other sections",
  {
    capacity: z.string().describe("New capacity, e.g. '4h', '6h', '2h30m'"),
  },
  ({ capacity }) => {
    ensureDir();
    if (!existsSync(MEMORY_PATH)) {
      writeFileSync(MEMORY_PATH, `## Settings\ndaily_capacity: ${capacity}\n`, "utf-8");
      return { content: [{ type: "text", text: `Set daily_capacity to ${capacity} (created memory.md)` }] };
    }
    let content = readFileSync(MEMORY_PATH, "utf-8");
    if (content.match(/^daily_capacity:.*/m)) {
      content = content.replace(/^daily_capacity:.*/m, `daily_capacity: ${capacity}`);
    } else if (content.includes("## Settings")) {
      content = content.replace("## Settings", `## Settings\ndaily_capacity: ${capacity}`);
    } else {
      content += `\n## Settings\ndaily_capacity: ${capacity}\n`;
    }
    writeFileSync(MEMORY_PATH, content, "utf-8");
    return { content: [{ type: "text", text: `daily_capacity set to ${capacity}` }] };
  }
);

// Add/update a project in memory.md
server.tool(
  "set_project",
  "Add or update a project in memory.md",
  {
    name: z.string().describe("Project name"),
    priority: z.number().describe("Priority (1 = highest)"),
    deadline: z.string().optional().describe("Deadline in YYYY-MM-DD format"),
  },
  ({ name, priority, deadline }) => {
    ensureDir();
    let content = existsSync(MEMORY_PATH) ? readFileSync(MEMORY_PATH, "utf-8") : "";
    let entry = `- ${name} | priority: ${priority}`;
    if (deadline) entry += ` | deadline: ${deadline}`;

    const lines = content.split("\n");
    const existingIdx = lines.findIndex((l) => l.includes(`- ${name} |`) || l.includes(`- ${name}\n`));

    if (existingIdx !== -1) {
      lines[existingIdx] = entry;
    } else {
      const projHeader = lines.findIndex((l) => l.trim() === "## Projects");
      if (projHeader !== -1) {
        lines.splice(projHeader + 1, 0, entry);
      } else {
        lines.unshift("## Projects", entry, "");
      }
    }

    writeFileSync(MEMORY_PATH, lines.join("\n"), "utf-8");
    return { content: [{ type: "text", text: `Project "${name}" set: priority ${priority}${deadline ? `, deadline ${deadline}` : ""}` }] };
  }
);

// Capture an idea to ideas.md (DayPilot Ideas tab), matching IdeasParser's
// `<!-- id: … created: … -->` + `## Title` + body block format.
function deriveIdeaTitle(body) {
  const first = (body.split("\n").find((l) => l.trim()) || "Untitled").trim();
  return first.length > 60 ? first.slice(0, 60).trim() + "…" : first;
}

function escapeIdeaBody(body) {
  // A body line that's itself an entry header would split the idea on re-parse —
  // break the match with a zero-width space after `<!--` (IdeasParser strips it).
  return body
    .split("\n")
    .map((l) => (l.trim().startsWith("<!-- id:") ? l.replace("<!--", "<!--​") : l))
    .join("\n");
}

function ideaTimestamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

server.tool(
  "add_idea",
  "Capture an idea/note to ~/scheduler/ideas.md (shown in DayPilot's Ideas tab). Use for thoughts that aren't tasks yet. Fields: body (the idea), title (optional — derived from the body if omitted).",
  {
    body: z.string().describe("The idea text (can be multiple lines)"),
    title: z.string().optional().describe("Optional short title; derived from body if omitted"),
  },
  ({ body, title }) => {
    ensureDir();
    const t = (title || "").trim();
    const b = (body || "").trim();
    if (!t && !b) return { content: [{ type: "text", text: "Error: title or body is required" }] };
    const finalTitle = t || deriveIdeaTitle(b);
    const id = randomUUID().replace(/-/g, "").slice(0, 8).toLowerCase();
    let content = existsSync(IDEAS_PATH) ? readFileSync(IDEAS_PATH, "utf-8") : "";
    if (!content) content = "# Ideas\n";
    if (!content.endsWith("\n")) content += "\n";
    content += `\n<!-- id: ${id} created: ${ideaTimestamp()} -->\n## ${finalTitle}\n`;
    if (b) content += escapeIdeaBody(b) + "\n";
    writeFileSync(IDEAS_PATH, content, "utf-8");
    return { content: [{ type: "text", text: `Idea saved: ${finalTitle}` }] };
  }
);

// Helper: log completed task to done.md
function logDone(rawTask) {
  ensureDir();
  const today = new Date().toISOString().split("T")[0];
  const header = `## ${today}`;

  let lines = [];
  if (existsSync(DONE_PATH)) {
    lines = readFileSync(DONE_PATH, "utf-8").split("\n");
  }

  const headerIdx = lines.findIndex((l) => l.trim() === header);
  const entry = `- [x] ${rawTask}`;

  if (headerIdx !== -1) {
    let insertAt = headerIdx + 1;
    while (insertAt < lines.length && lines[insertAt].trim() && !lines[insertAt].trim().startsWith("## ")) {
      insertAt++;
    }
    lines.splice(insertAt, 0, entry);
  } else {
    let insertAt = 0;
    if (lines.length > 0 && lines[0].startsWith("# ")) {
      insertAt = 1;
      if (insertAt < lines.length && lines[insertAt] === "") insertAt = 2;
    }
    lines.splice(insertAt, 0, header, entry, "");
  }

  writeFileSync(DONE_PATH, lines.join("\n"), "utf-8");
}

const transport = new StdioServerTransport();
await server.connect(transport);
