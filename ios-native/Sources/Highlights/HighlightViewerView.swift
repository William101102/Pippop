import SwiftUI

/// Full-screen story viewer — port of the web app's `HighlightViewer`.
struct HighlightViewerView: View {
    let author: Profile
    let isMine: Bool
    let highlights: [Highlight]
    var onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current = highlights[safe: index] {
                VStack(spacing: 0) {
                    progressBar
                    header(current)

                    ZStack {
                        if let urlString = current.mediaUrl, let url = URL(string: urlString) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView().tint(.white)
                            }
                        } else {
                            VStack {
                                Spacer()
                                Text(current.body.isEmpty ? "✨" : current.body)
                                    .font(Theme.Font.display(24))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(24)
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        Color.clear.contentShape(Rectangle()).frame(width: 80)
                            .onTapGesture { step(-1) }
                    }
                    .overlay(alignment: .trailing) {
                        Color.clear.contentShape(Rectangle()).frame(width: 80)
                            .onTapGesture { step(1) }
                    }

                    if current.mediaUrl != nil, !current.body.isEmpty {
                        Text(current.body)
                            .font(Theme.Font.body(13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4))
                    }
                }
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(highlights.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? .white : .white.opacity(0.3))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func header(_ current: Highlight) -> some View {
        HStack(spacing: 10) {
            AvatarView(profile: author, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(author.displayName).font(Theme.Font.body(13, weight: .bold)).foregroundStyle(.white)
                Text(current.createdAt.relativeLabel).font(Theme.Font.body(10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            if isMine {
                Button {
                    onDelete(current.id)
                    if highlights.count <= 1 { dismiss() } else { step(1) }
                } label: {
                    Image(systemName: "trash").foregroundStyle(.white)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        if next < 0 { return }
        if next >= highlights.count { dismiss(); return }
        index = next
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
