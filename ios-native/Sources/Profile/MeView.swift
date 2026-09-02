import SwiftUI

/// The Me tab — your own profile, Ghost Mode, and account actions.
struct MeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var statusText = ""
    @State private var savingProfile = false
    @State private var saveNotice: String?

    @State private var changingGhostMode = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    @State private var zones: [Zone] = []
    @State private var creatingZone = false
    @State private var newZoneLabel = ""
    @State private var newZoneEmoji = ZonesService.emojiChoices[0]
    @State private var zoneBusy = false
    @State private var zoneMessage: String?
    @State private var frequentPlaces: [FrequentPlace] = []
    @State private var loadingWorld = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if let profile = auth.profile {
                            header(profile)
                            editCard
                            ghostModeCard
                            myWorldCard
                        }
                        accountCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Font.body(14, weight: .bold))
                }
            }
        }
        .onAppear {
            displayName = auth.profile?.displayName ?? ""
            username = auth.profile?.username ?? ""
            statusText = auth.profile?.statusText ?? ""
        }
        .task { await loadWorld() }
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete everything", role: .destructive) {
                Task {
                    do { try await auth.deleteAccount() }
                    catch { deleteError = error.localizedDescription }
                }
            }
        } message: {
            Text("This removes your profile, location history, and friendships. It can't be undone.")
        }
        .alert("Couldn't delete account", isPresented: .init(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func header(_ profile: Profile) -> some View {
        VStack(spacing: 10) {
            AvatarView(profile: profile, size: 84)
            Text("@\(profile.username)")
                .font(Theme.Font.body(12, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var editCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROFILE")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.3)
                .foregroundStyle(Theme.pink)

            field("Display name", text: $displayName)
            usernameField
            field("Status (optional)", text: $statusText)

            if let saveNotice {
                Text(saveNotice)
                    .font(Theme.Font.body(11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            Button {
                Task { await save() }
            } label: {
                Text(savingProfile ? "Saving…" : "Save")
                    .font(Theme.Font.body(14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(
                savingProfile
                || displayName.trimmingCharacters(in: .whitespaces).isEmpty
                || username.trimmingCharacters(in: .whitespaces).count < 3
            )
            .pressable()
        }
        .padding(16)
        .floatingCard(radius: 24)
    }

    private var ghostModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GHOST MODE")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.3)
                .foregroundStyle(Theme.pink)

            ForEach(GhostMode.allCases, id: \.self) { mode in
                Button {
                    Task { await setGhostMode(mode) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(location.ghostMode == mode ? .white : Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(
                                location.ghostMode == mode ? Theme.violet : Color(hex: 0xF4F0F6),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.title)
                                .font(Theme.Font.body(13, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text(mode.detail)
                                .font(Theme.Font.body(10, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if location.ghostMode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.violet)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .disabled(changingGhostMode)
            }
        }
        .padding(16)
        .floatingCard(radius: 24)
    }

    /// "My World": Zenlands (hand-named, friend-visible places) and a
    /// footprints summary — port of the web app's `ZonesSection` and
    /// `FootprintsPanel`, which live in its "World" panel (the dock slot the
    /// native app repurposed for this Me/settings tab, so they landed here
    /// instead of getting their own screen).
    ///
    /// This shows the *list* of frequent places and their dwell time, not
    /// the web version's live heatmap overlay on the map — that needs a
    /// custom `MKOverlay`/`MKOverlayRenderer` on `MapScreen`, which is a
    /// bigger, separate piece of work than the data layer here.
    private var myWorldCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MY WORLD")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.3)
                .foregroundStyle(Theme.pink)

            Text("ZENLANDS")
                .font(Theme.Font.body(9, weight: .heavy))
                .foregroundStyle(Theme.muted)

            if loadingWorld {
                ProgressView().tint(Theme.violet).frame(maxWidth: .infinity)
            } else {
                ForEach(zones) { zone in
                    HStack(spacing: 10) {
                        Text(zone.emoji).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(zone.label).font(Theme.Font.body(13, weight: .bold)).foregroundStyle(Theme.ink)
                            Text("Friends can see · \(zone.radiusM)m radius").font(Theme.Font.body(10, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button {
                            Task { await deleteZone(zone) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        .disabled(zoneBusy)
                    }
                    .padding(.vertical, 4)
                }

                if creatingZone {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(ZonesService.emojiChoices, id: \.self) { emoji in
                                Button { newZoneEmoji = emoji } label: {
                                    Text(emoji).font(.system(size: 16))
                                        .frame(width: 32, height: 32)
                                        .background(
                                            newZoneEmoji == emoji ? Theme.violet.opacity(0.15) : Color(hex: 0xF4F0F6),
                                            in: Circle()
                                        )
                                }
                            }
                        }
                        TextField("e.g. Gym", text: $newZoneLabel)
                            .font(Theme.Font.body(13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .tint(Theme.violet)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(hex: 0xF4F0F6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        if let zoneMessage {
                            Text(zoneMessage).font(Theme.Font.body(10, weight: .medium)).foregroundStyle(Theme.coral)
                        }
                        HStack(spacing: 8) {
                            Button("Cancel") { creatingZone = false; newZoneLabel = "" }
                                .font(Theme.Font.body(12, weight: .bold))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Button {
                                Task { await createZone() }
                            } label: {
                                Text(zoneBusy ? "Saving…" : "Create at current location")
                                    .font(Theme.Font.body(12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Theme.brandGradient, in: Capsule())
                            }
                            .disabled(zoneBusy)
                        }
                    }
                } else {
                    Button {
                        creatingZone = true
                    } label: {
                        Label("Create a Zenland using your current location", systemImage: "plus.circle.fill")
                            .font(Theme.Font.body(12, weight: .bold))
                            .foregroundStyle(Theme.violet)
                    }
                }

                Divider().padding(.vertical, 4)

                Text("FOOTPRINTS · LAST 30 DAYS")
                    .font(Theme.Font.body(9, weight: .heavy))
                    .foregroundStyle(Theme.muted)

                if frequentPlaces.isEmpty {
                    Text("No footprints yet — get out and about with Pinpop.")
                        .font(Theme.Font.body(11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(frequentPlaces.prefix(5).enumerated()), id: \.offset) { index, place in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(Theme.Font.body(11, weight: .heavy))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(place.lat, specifier: "%.3f"), \(place.lng, specifier: "%.3f")")
                                    .font(Theme.Font.body(12, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                Text("\(FootprintsService.humanMinutes(place.minutes)) · visited \(place.visits)x")
                                    .font(Theme.Font.body(10, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(16)
        .floatingCard(radius: 24)
    }

    private var accountCard: some View {
        VStack(spacing: 10) {
            Button { confirmSignOut = true } label: {
                Text("Sign out")
                    .font(Theme.Font.body(14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.ink.opacity(0.12), lineWidth: 1)
                    )
            }
            .pressable()

            Button { confirmDelete = true } label: {
                Text("Delete account")
                    .font(Theme.Font.body(13, weight: .bold))
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .pressable()
        }
        .padding(.top, 4)
    }

    /// Sign-up bootstraps everyone with a random `@user_xxxxxxxx` handle
    /// (a Postgres trigger, not this screen) — this is where you replace it
    /// with a real one.
    private var usernameField: some View {
        HStack(spacing: 8) {
            Text("@")
                .font(Theme.Font.body(14, weight: .bold))
                .foregroundStyle(Theme.muted)
            TextField("username", text: $username)
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .tint(Theme.violet)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(Theme.Font.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .tint(Theme.violet)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .autocorrectionDisabled()
    }

    private func save() async {
        savingProfile = true
        let trimmedStatus = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = await auth.updateProfile(
            displayName: displayName,
            statusText: trimmedStatus.isEmpty ? nil : trimmedStatus,
            username: username
        )
        saveNotice = error ?? "Saved."
        savingProfile = false
    }

    private func setGhostMode(_ mode: GhostMode) async {
        guard let ownerId = auth.profile?.id, !changingGhostMode else { return }
        changingGhostMode = true
        location.ghostMode = mode
        try? await FriendsService.setGhostMode(mode, ownerId: ownerId, frozen: location.current)
        changingGhostMode = false
    }

    private func loadWorld() async {
        loadingWorld = zones.isEmpty && frequentPlaces.isEmpty
        async let zonesTask = ZonesService.loadVisible()
        async let placesTask = FootprintsService.loadFrequentPlaces()
        zones = (try? await zonesTask) ?? []
        frequentPlaces = (try? await placesTask) ?? []
        loadingWorld = false
    }

    private func createZone() async {
        guard let ownerId = auth.profile?.id, let fix = location.current else {
            zoneMessage = "Turn on location before creating a Zenland"
            return
        }
        let label = newZoneLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            zoneMessage = "Give this Zenland a name"
            return
        }
        zoneBusy = true
        zoneMessage = nil
        defer { zoneBusy = false }
        do {
            let zone = try await ZonesService.create(ownerId: ownerId, label: label, emoji: newZoneEmoji, lat: fix.lat, lng: fix.lng)
            zones.insert(zone, at: 0)
            newZoneLabel = ""
            creatingZone = false
        } catch {
            zoneMessage = "Couldn't create that Zenland — try again."
        }
    }

    private func deleteZone(_ zone: Zone) async {
        zoneBusy = true
        defer { zoneBusy = false }
        try? await ZonesService.delete(zone.id)
        zones.removeAll { $0.id == zone.id }
    }
}
