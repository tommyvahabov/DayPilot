import SwiftUI
import AppKit

/// Full task editor presented as a modal sheet: title, project, effort, due,
/// snooze, notes, and attachments — plus delete. The single save path goes
/// through `store.applyTaskEdit`.
struct TaskEditorSheet: View {
    let store: ScheduleStore
    let item: TodoItem

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var project: String
    @State private var effort: String
    @State private var deadline: Date?
    @State private var deferUntil: Date?
    @State private var priority: Int?
    @State private var notes: String
    @State private var attachments: [Attachment]
    /// Attachments imported during this session — deleted on cancel since they
    /// were never persisted.
    @State private var sessionAdded: Set<String> = []
    @State private var confirmDelete = false

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(store: ScheduleStore, item: TodoItem) {
        self.store = store
        self.item = item
        _title = State(initialValue: item.title)
        _project = State(initialValue: item.project ?? "")
        _effort = State(initialValue: DurationParser.format(minutes: item.effortMinutes))
        _deadline = State(initialValue: item.deadline)
        _deferUntil = State(initialValue: item.deferUntil)
        _priority = State(initialValue: item.priority)
        _notes = State(initialValue: item.notes.joined(separator: "\n"))
        _attachments = State(initialValue: item.attachments)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleField
                    projectField
                    priorityField
                    effortField
                    dateField(title: "Due", icon: "flag.fill", date: $deadline, accent: .orange)
                    dateField(title: "Snooze", icon: "moon.zzz.fill", date: $deferUntil, accent: .indigo, includeToday: false)
                    notesField
                    attachmentsField
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 600)
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Label("Edit task", systemImage: "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if item.addedBy == "claude" {
                Label("from Claude", systemImage: "sparkle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete task", role: .destructive) {
                    store.removeTask(item)
                    dismiss()
                }
            } message: {
                Text("“\(item.title)” and its attachments will be removed. The change is git-backed.")
            }

            Spacer()

            Button("Cancel") { cancel() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Fields

    private var titleField: some View {
        fieldGroup("Title") {
            TextField("What needs doing?", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1...3)
                .padding(10)
                .background(fieldBackground)
        }
    }

    private var projectField: some View {
        fieldGroup("Project") {
            VStack(alignment: .leading, spacing: 8) {
                FlowChips(
                    options: store.context.projects.map(\.name),
                    selection: project,
                    color: { ProjectColor.color(for: $0) },
                    onTap: { name in project = (project == name) ? "" : name }
                )
                TextField("Project name (type to add a new one)", text: $project)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(fieldBackground)
            }
        }
    }

    private var priorityField: some View {
        fieldGroup("Priority") {
            HStack(spacing: 8) {
                chip("None", selected: priority == nil, color: .gray) { priority = nil }
                ForEach(PriorityStyle.levels, id: \.self) { p in
                    chip(PriorityStyle.name(p), selected: priority == p, color: PriorityStyle.color(p)) {
                        priority = (priority == p) ? nil : p
                    }
                }
                Spacer()
            }
        }
    }

    private var effortField: some View {
        fieldGroup("Effort") {
            VStack(alignment: .leading, spacing: 8) {
                FlowChips(
                    options: ["15m", "30m", "45m", "1h", "1h 30m", "2h", "3h"],
                    selection: effort,
                    color: { _ in .accentColor },
                    onTap: { v in effort = (effort == v) ? "" : v }
                )
                TextField("e.g. 90m or 1h 30m", text: $effort)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(fieldBackground)
            }
        }
    }

    private func dateField(title: String, icon: String, date: Binding<Date?>, accent: Color, includeToday: Bool = true) -> some View {
        fieldGroup(title) {
            HStack(spacing: 8) {
                chip("None", selected: date.wrappedValue == nil, color: accent) { date.wrappedValue = nil }
                if includeToday {
                    chip("Today", selected: isSameDay(date.wrappedValue, .now), color: accent) {
                        date.wrappedValue = Calendar.current.startOfDay(for: Date())
                    }
                }
                chip("Tomorrow", selected: isSameDay(date.wrappedValue, dayOffset(1)), color: accent) {
                    date.wrappedValue = dayOffset(1)
                }
                if date.wrappedValue != nil {
                    DatePicker("", selection: Binding(
                        get: { date.wrappedValue ?? Date() },
                        set: { date.wrappedValue = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
                Spacer()
            }
        }
    }

    private var notesField: some View {
        fieldGroup("Notes") {
            TextEditor(text: $notes)
                .font(.system(size: 12.5))
                .frame(minHeight: 80, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(fieldBackground)
        }
    }

    private var attachmentsField: some View {
        fieldGroup("Attachments") {
            VStack(alignment: .leading, spacing: 10) {
                if attachments.isEmpty {
                    Text("Drop nothing here — use the buttons below to attach screenshots, PDFs, anything.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    AttachmentGalleryView(attachments: attachments, thumbSide: 76, onRemove: remove)
                }
                HStack(spacing: 8) {
                    Button(action: pickFiles) {
                        Label("Add file…", systemImage: "paperclip")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: pasteImage) {
                        Label("Paste image", systemImage: "doc.on.clipboard")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!pasteboardHasImage)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func chip(_ label: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? .white : .primary.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? color : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Attachments

    private var pasteboardHasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let added = AttachmentService.importFile(from: url) {
                attachments.append(added)
                sessionAdded.insert(added.relativePath)
            }
        }
    }

    private func pasteImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        if let added = AttachmentService.importImageData(png) {
            attachments.append(added)
            sessionAdded.insert(added.relativePath)
        }
    }

    private func remove(_ attachment: Attachment) {
        attachments.removeAll { $0 == attachment }
        // If it was imported this session it will never be persisted — drop the file now.
        if sessionAdded.remove(attachment.relativePath) != nil {
            AttachmentService.deleteFile(attachment)
        }
    }

    // MARK: - Save / cancel

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.applyTaskEdit(
            item,
            title: title,
            project: project,
            effort: effort,
            deadline: deadline.map { Self.iso.string(from: $0) } ?? "",
            deferUntil: deferUntil.map { Self.iso.string(from: $0) } ?? "",
            priority: priority,
            notes: notes
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            attachments: attachments
        )
        dismiss()
    }

    private func cancel() {
        // Clean up files imported this session but never saved.
        for path in sessionAdded {
            AttachmentService.deleteFile(Attachment(relativePath: path))
        }
        dismiss()
    }

    // MARK: - Date helpers

    private func dayOffset(_ days: Int) -> Date {
        Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: days, to: Date())!)
    }

    private func isSameDay(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }
}

/// A wrapping row of selectable capsule chips.
struct FlowChips: View {
    let options: [String]
    let selection: String
    var color: (String) -> Color = { _ in .accentColor }
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button(action: { onTap(option) }) {
                    Text(option)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? .white : .primary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(selected ? color(option) : Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal flow layout that wraps its subviews onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        let height = rows.reduce(CGFloat(0)) { acc, row in
            acc + (row.map(\.height).max() ?? 0) + spacing
        } - (rows.isEmpty ? 0 : spacing)
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
