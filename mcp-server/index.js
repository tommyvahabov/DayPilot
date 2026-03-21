import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const TODOS_PATH = join(homedir(), "scheduler", "todos.md");
const MEMORY_PATH = join(homedir(), "scheduler", "memory.md");

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

const server = new McpServer({
  name: "daypilot",
  version: "1.0.0",
});

// List all tasks
server.tool("list_tasks", "List all tasks from ~/scheduler/todos.md", {}, () => {
  const lines = readLines();
  const tasks = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    const openMatch = line.match(/^- \[ \] (.+)/);
    const doneMatch = line.match(/^- \[x\] (.+)/);
    if (openMatch) {
      tasks.push({ line: i, status: "open", raw: openMatch[1] });
    } else if (doneMatch) {
      tasks.push({ line: i, status: "done", raw: doneMatch[1] });
    }
  }
  return { content: [{ type: "text", text: JSON.stringify(tasks, null, 2) }] };
});

// Add a task
server.tool(
  "add_task",
  "Add a new task to ~/scheduler/todos.md. Fields: title (required), project, effort (e.g. '30m', '1h'), deadline (YYYY-MM-DD)",
  {
    title: z.string().describe("Task title"),
    project: z.string().optional().describe("Project name"),
    effort: z.string().optional().describe("Effort estimate, e.g. '30m', '1h', '1h30m'"),
    deadline: z.string().optional().describe("Deadline in YYYY-MM-DD format"),
  },
  ({ title, project, effort, deadline }) => {
    const lines = readLines();
    let task = `- [ ] ${title}`;
    if (project) task += ` | project: ${project}`;
    if (effort) task += ` | effort: ${effort}`;
    if (deadline) task += ` | deadline: ${deadline}`;
    lines.push(task);
    writeLines(lines);
    return { content: [{ type: "text", text: `Added: ${task}` }] };
  }
);

// Complete a task
server.tool(
  "complete_task",
  "Mark a task as done by its title (partial match)",
  {
    title: z.string().describe("Task title or partial match"),
  },
  ({ title }) => {
    const lines = readLines();
    const lower = title.toLowerCase();
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes("- [ ] ") && lines[i].toLowerCase().includes(lower)) {
        lines[i] = lines[i].replace("- [ ] ", "- [x] ");
        writeLines(lines);
        return { content: [{ type: "text", text: `Completed: ${lines[i].trim()}` }] };
      }
    }
    return { content: [{ type: "text", text: `No open task matching "${title}" found` }] };
  }
);

// Remove a task
server.tool(
  "remove_task",
  "Remove a task entirely by its title (partial match)",
  {
    title: z.string().describe("Task title or partial match"),
  },
  ({ title }) => {
    const lines = readLines();
    const lower = title.toLowerCase();
    for (let i = 0; i < lines.length; i++) {
      if ((lines[i].includes("- [ ] ") || lines[i].includes("- [x] ")) && lines[i].toLowerCase().includes(lower)) {
        const removed = lines.splice(i, 1)[0];
        writeLines(lines);
        return { content: [{ type: "text", text: `Removed: ${removed.trim()}` }] };
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

const transport = new StdioServerTransport();
await server.connect(transport);
