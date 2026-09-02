import SwiftUI

/// Friend picker + name field for starting a group chat — port of the web
/// app's `NewGroupSheet`.
struct NewGroupView: View {
    let friends: [Friend]
    var onCreated: (ChatGroup) -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selected: Set<UUID> = []
    @State private var creating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GROUP NAME")
                                .font(Theme.Font.body(10, weight: .heavy))
                                .kerning(1.2)
                                .foregroundStyle(Theme.muted)
                            TextField("Weekend crew", text: $name)
                                .font(Theme.Font.body(15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .tint(Theme.violet)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ADD FRIENDS (\(selected.count))")
                                .font(Theme.Font.body(10, weight: .heavy))
                                .kerning(1.2)
                                .foregroundStyle(Theme.muted)

                            if friends.isEmpty {
                                Text("Add some friends first, then start a group.")
                                    .font(Theme.Font.body(12, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(friends) { friend in
                                        friendRow(friend)
                                    }
                                }
                            }
                        }

                        if let errorText {
                            Text(errorText)
                                .font(Theme.Font.body(12, weight: .semibold))
                                .foregroundStyle(Theme.coral)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(creating ? "Creating…" : "Create") { Task { await create() } }
                        .font(Theme.Font.body(14, weight: .bold))
                        .disabled(creating || !canCreate)
                }
            }
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selected.count >= 2
    }

    private func friendRow(_ friend: Friend) -> some View {
        let isOn = selected.contains(friend.id)
        return Button {
            if isOn { selected.remove(friend.id) } else { selected.insert(friend.id) }
        } label: {
            HStack(spacing: 12) {
                AvatarView(profile: friend.profile, size: 42)
                Text(friend.displayName)
                    .font(Theme.Font.body(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.muted.opacity(0.4)))
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func create() async {
        guard let meId = auth.profile?.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard selected.count >= 2 else {
            errorText = "Pick at least 2 friends for a group."
            return
        }
        creating = true
        errorText = nil
        defer { creating = false }
        do {
            let group = try await GroupsService.create(ownerId: meId, name: trimmed, memberIds: Array(selected))
            onCreated(group)
            dismiss()
        } catch {
            errorText = "Couldn't create that group — try again."
        }
    }
}
