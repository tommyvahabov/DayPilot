import SwiftUI
import AppKit

/// Read-only grid of attachment thumbnails. Click to open in the default app.
struct AttachmentGalleryView: View {
    let attachments: [Attachment]
    var thumbSide: CGFloat = 72
    var onRemove: ((Attachment) -> Void)? = nil

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbSide, maximum: thumbSide * 1.6), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentThumbView(attachment: attachment, side: thumbSide, onRemove: onRemove)
            }
        }
    }
}

struct AttachmentThumbView: View {
    let attachment: Attachment
    var side: CGFloat = 72
    var onRemove: ((Attachment) -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Button(action: { AttachmentService.open(attachment) }) {
                    thumb
                }
                .buttonStyle(.plain)
                .help("Open \(attachment.displayName)")

                if let onRemove, hovering {
                    Button(action: { onRemove(attachment) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .padding(3)
                    .help("Remove attachment")
                }
            }

            Text(attachment.displayName)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: side)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { AttachmentService.open(attachment) }
            Button("Reveal in Finder") { AttachmentService.revealInFinder(attachment) }
            if let onRemove {
                Divider()
                Button(role: .destructive) { onRemove(attachment) } label: { Text("Remove") }
            }
        }
    }

    @ViewBuilder
    private var thumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))

            if let nsImage = AttachmentService.thumbnail(for: attachment) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if AttachmentService.exists(attachment) {
                VStack(spacing: 4) {
                    Image(nsImage: AttachmentService.fileIcon(for: attachment))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: side * 0.5, height: side * 0.5)
                    Text(attachment.ext.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: side * 0.3))
                        .foregroundStyle(.tertiary)
                    Text("missing")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: side, height: side)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.18 : 0.08), lineWidth: 1)
        )
    }
}
