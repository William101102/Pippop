import SwiftUI

/// A 1:1 conversation thread — port of the web app's `ChatPanel`.
///
/// There's no Realtime subscription here yet (the web app gets live updates
/// via `supabase_realtime` on `messages`; wiring that up natively is future
/// work). Instead this polls every few seconds while the screen is visible,
/// which is simple and good enough for a chat that's mostly used
/// synchronously — see the `poll()` loop below.
struct ChatView: View {
    let friend: Friend

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, mine: message.senderId == auth.profile?.id)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            composer
        }
        .background(Theme.ground)
        .task {
            await load()
            await markRead()
            startPolling()
        }
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Theme.fill, in: Circle())
            }
            .pressable()
            AvatarView(profile: friend.profile, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.displayName)
                    .font(Theme.Font.body(14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text([friend.profile.statusEmoji, friend.profile.statusText].compactMap { $0 }.joined(separator: " "))
                    .font(Theme.Font.body(10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Send a message…", text: $draft, axis: .vertical)
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .tint(Theme.violet)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.brandGradient, in: Circle())
            }
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .pressable()
        }
        .padding(12)
        .background(Theme.surface)
    }

    private func load() async {
        guard let meId = auth.profile?.id else { return }
        messages = (try? await MessagesService.loadThread(meId: meId, friendId: friend.id)) ?? messages
    }

    private func markRead() async {
        guard let meId = auth.profile?.id else { return }
        try? await MessagesService.markThreadRead(meId: meId, friendId: friend.id)
    }

    private func send() async {
        guard let meId = auth.profile?.id else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sending = true
        defer { sending = false }
        do {
            try await MessagesService.send(from: meId, to: friend.id, body: text)
            await load()
        } catch {
            draft = text // hand the text back so nothing typed is lost
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                await load()
            }
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    let mine: Bool

    /// Port of `.chat-bubble` — 18px everywhere except the "tail" corner
    /// (bottom-right for mine, bottom-left for theirs), flattened to 6px so
    /// the bubble reads as pointing toward its sender.
    private var shape: UnevenRoundedRectangle {
        .rect(
            topLeadingRadius: 18,
            bottomLeadingRadius: mine ? 18 : 6,
            bottomTrailingRadius: mine ? 6 : 18,
            topTrailingRadius: 18
        )
    }

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(message.body)
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(mine ? .white : Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    mine ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.fill),
                    in: shape
                )
            if !mine { Spacer(minLength: 40) }
        }
    }
}
