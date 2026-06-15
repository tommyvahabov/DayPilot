import SwiftUI

/// Free-form idea / journal space. Capture at the top, browse the feed below.
/// Backed by ~/scheduler/ideas.md, watched and git-committed like everything else.
struct IdeasView: View {
    @Bindable var store: ScheduleStore

    @State private var query = ""

    private var filtered: [Idea] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.ideas }
        return store.ideas.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)

            IdeaComposerView(store: store)
                .padding(.horizontal, 24)

            if store.ideas.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { idea in
                            IdeaCardView(store: store, idea: idea)
                        }
                        if filtered.isEmpty {
                            Text("No ideas match “\(query)”.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ideas")
                    .font(.system(size: 25, weight: .bold))
                Text(store.ideas.isEmpty ? "Capture anything — sort it out later." : "\(store.ideas.count) captured")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.ideas.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 160)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.background.secondary))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: 30))
                .foregroundStyle(.yellow.opacity(0.8))
            Text("No ideas yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Jot the half-formed ones here before they evaporate.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IdeaComposerView: View {
    let store: ScheduleStore

    @State private var title = ""
    @State private var body_ = ""
    @State private var expanded = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(.yellow)
                TextField("New idea…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .focused($titleFocused)
                    .onSubmit { if !expanded { capture() } }
                    .onTapGesture { expanded = true }
                if !expanded && (!title.isEmpty) {
                    captureButton
                }
            }

            if expanded {
                TextEditor(text: $body_)
                    .font(.system(size: 12.5))
                    .frame(minHeight: 70, maxHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(alignment: .topLeading) {
                        if body_.isEmpty {
                            Text("Flesh it out… (optional)")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Text("⌘↵ to capture")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear") { clear() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(title.isEmpty && body_.isEmpty)
                    captureButton
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.yellow.opacity(expanded ? 0.3 : 0.12), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: expanded)
    }

    private var captureButton: some View {
        Button(action: capture) {
            Text("Capture")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && body_.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func capture() {
        store.addIdea(title: title, body: body_)
        clear()
    }

    private func clear() {
        title = ""
        body_ = ""
        withAnimation { expanded = false }
        titleFocused = false
    }
}

struct IdeaCardView: View {
    let store: ScheduleStore
    let idea: Idea

    @State private var expanded = false
    @State private var editing = false
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var confirmDelete = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let absolute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f
    }()

    private var timeText: String {
        guard idea.createdAt.timeIntervalSince1970 > 0 else { return "" }
        if Date().timeIntervalSince(idea.createdAt) < 60 * 60 * 18 {
            return Self.relative.localizedString(for: idea.createdAt, relativeTo: Date())
        }
        return Self.absolute.string(from: idea.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editing { editForm } else { display }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(idea.pinned ? Color.yellow.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: Display

    private var display: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if idea.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .padding(.top, 3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(idea.title.isEmpty ? "Untitled" : idea.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !timeText.isEmpty {
                        Text(timeText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                menu
            }

            if !idea.body.isEmpty {
                Text(idea.body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }

                if bodyIsLong {
                    Button(expanded ? "Show less" : "Show more") {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 11))
                }
            }
        }
    }

    private var bodyIsLong: Bool {
        idea.body.count > 240 || idea.body.split(separator: "\n").count > 4
    }

    private var menu: some View {
        Menu {
            Button { beginEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button { store.toggleIdeaPin(idea.id) } label: {
                Label(idea.pinned ? "Unpin" : "Pin", systemImage: idea.pinned ? "pin.slash" : "pin")
            }
            Button { store.promoteIdeaToTask(idea, removeIdea: false) } label: {
                Label("Make a task", systemImage: "checklist")
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .confirmationDialog("Delete this idea?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.deleteIdea(idea.id) }
        }
    }

    // MARK: Edit

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))

            TextEditor(text: $draftBody)
                .font(.system(size: 12.5))
                .frame(minHeight: 90, maxHeight: 240)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))

            HStack {
                Spacer()
                Button("Cancel") { editing = false }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Button("Save") {
                    store.updateIdea(idea.id, title: draftTitle, body: draftBody)
                    editing = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty && draftBody.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func beginEdit() {
        draftTitle = idea.title
        draftBody = idea.body
        withAnimation(.easeInOut(duration: 0.12)) { editing = true }
    }
}
