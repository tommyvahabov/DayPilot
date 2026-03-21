import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const TODOS_PATH = join(homedir(), "scheduler", "todos.md");
const MEMORY_PATH = join(homedir(), "scheduler", "memory.md");
const DONE_PATH = join(homedir(), "scheduler", "done.md");

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

// List all tasks (with notes)
server.tool("list_tasks", "List all tasks from ~/scheduler/todos.md (includes notes)", {}, () => {
  const lines = readLines();
  const tasks = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    const openMatch = line.match(/^- \[ \] (.+)/);
    const doneMatch = line.match(/^- \[x\] (.+)/);
    if (openMatch) {
      const notes = collectNotes(lines, i);
      tasks.push({ line: i, status: "open", raw: openMatch[1], notes });
      i += notes.length;
    } else if (doneMatch) {
      const notes = collectNotes(lines, i);
      tasks.push({ line: i, status: "done", raw: doneMatch[1], notes });
      i += notes.length;
    }
  }
  return { content: [{ type: "text", text: JSON.stringify(tasks, null, 2) }] };
});

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
