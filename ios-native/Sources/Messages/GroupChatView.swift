import SwiftUI

/// A group chat thread — port of the web app's `GroupChatPanel`. Reuses the
/// same bubble-and-polling approach as `ChatView`, but adds a sender
/// avatar/name above each message from someone else, since a group thread
/// (unlike 1:1) can't rely on bubble side alone to say who's speaking.
struct GroupChatView: View {
    let group: ChatGroup

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var pollTask: Task<Void, Never>?

    private var membersById: [UUID: Profile] {
        Dictionary(uniqueKeysWithValues: group.members.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            let mine = message.senderId == auth.profile?.id
                            let showsSender = !mine && (index == 0 || messages[index - 1].senderId != message.senderId)
                            GroupMessageRow(
                                message: message,
                                sender: membersById[message.senderId],
                                mine: mine,
                                showsSender: showsSender
                            )
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
                    .background(Color(hex: 0xF4F0F6), in: Circle())
            }
            .pressable()

            GroupAvatarStack(members: group.members)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(Theme.Font.body(14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(group.members.count) people")
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
                .background(Color(hex: 0xF4F0F6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

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
        messages = (try? await GroupsService.loadThread(groupId: group.id)) ?? messages
    }

    private func send() async {
        guard let meId = auth.profile?.id else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sending = true
        defer { sending = false }
        do {
            try await GroupsService.send(senderId: meId, groupId: group.id, body: text)
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

private struct GroupMessageRow: View {
    let message: Message
    let sender: Profile?
    let mine: Bool
    let showsSender: Bool

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if showsSender, let sender {
                Text(sender.displayName)
                    .font(Theme.Font.body(10, weight: .heavy))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 4)
            }
            HStack {
                if mine { Spacer(minLength: 40) }
                Text(message.body)
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(mine ? .white : Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        mine ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color(hex: 0xF4F0F6)),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                if !mine { Spacer(minLength: 40) }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

/// A small overlapping-avatars stack for a group's header, capped at three
/// visible circles plus a "+N" overflow badge.
private struct GroupAvatarStack: View {
    let members: [Profile]

    var body: some View {
        let shown = Array(members.prefix(3))
        let overflow = members.count - shown.count

        HStack(spacing: -10) {
            ForEach(shown) { member in
                AvatarView(profile: member, size: 32)
                    .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(Theme.Font.body(10, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0xF4F0F6))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
            }
        }
    }
}
