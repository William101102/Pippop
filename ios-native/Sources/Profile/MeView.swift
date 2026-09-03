import PhotosUI
import SwiftUI

/// The Me tab — your own profile, Ghost Mode, and account actions.
struct MeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var location
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var statusText = ""
    @State private var savingProfile = false
    @State private var saveNotice: String?

    @State private var avatarItem: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var avatarError: String?

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
                        // Last of the settings cards — the account actions
                        // below it are destructive, so they stay at the very
                        // bottom where iOS users expect them.
                        appearanceCard
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
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
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

    /// Port of `.profile-spotlight` + `.avatar-editor`: your avatar with a
    /// violet "Change avatar" pill hanging off the bottom edge, and your
    /// handle/name beside it on a soft gradient card.
    private func header(_ profile: Profile) -> some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                AvatarView(profile: profile, size: 70, borderWidth: 4, showStatus: true)

                PhotosPicker(selection: $avatarItem, matching: .images) {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill").font(.system(size: 9))
                        Text(uploadingAvatar ? "Uploading…" : "Change avatar")
                    }
                    .font(Theme.Font.body(8, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Theme.violet, in: Capsule())
                    .overlay(Capsule().stroke(.white, lineWidth: 2))
                    .shadow(color: Color(hex: 0x472C9F).opacity(0.25), radius: 6, y: 5)
                }
                .disabled(uploadingAvatar)
                .opacity(uploadingAvatar ? 0.65 : 1)
                .offset(y: 15)
            }
            .padding(.bottom, 15)

            VStack(alignment: .leading, spacing: 2) {
                Text("@\(profile.username)")
                    .font(Theme.Font.body(11, weight: .heavy))
                    .foregroundStyle(Theme.violet)
                Text(profile.displayName)
                    .font(Theme.Font.display(20))
                    .foregroundStyle(Theme.ink)
                Text(avatarError ?? "Makes you easy to spot on the map")
                    .font(Theme.Font.body(11, weight: .medium))
                    .foregroundStyle(avatarError == nil ? Theme.muted : Theme.dangerInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Theme.adaptive(light: 0xFFF0E8, dark: 0x33262C), Theme.adaptive(light: 0xF0EAFF, dark: 0x272040)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
    }

    /// Picks the photo apart on the main actor, hands the `UIImage` to
    /// `ProfileService`, then asks `AuthService` to re-read the row so the
    /// new avatar appears everywhere it's shown (map pin, rails, rows).
    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let userId = auth.profile?.id else { return }
        uploadingAvatar = true
        avatarError = nil
        defer {
            uploadingAvatar = false
            avatarItem = nil
        }
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                avatarError = "Couldn't read that photo — try another one"
                return
            }
            try await ProfileService.uploadAvatar(userId: userId, image: image)
            await auth.refreshProfile()
            Haptics.shared.play(.success)
        } catch {
            avatarError = (error as? LocalizedError)?.errorDescription ?? "Couldn't update your photo"
        }
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
                                location.ghostMode == mode ? Theme.violet : Theme.fill,
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
                                            newZoneEmoji == emoji ? Theme.violet.opacity(0.15) : Theme.fill,
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
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    /// Day / Night / Auto, side by side. Each tile is a little mock-up of
    /// the app in that mode rather than just an icon — you can see what
    /// you're picking before you pick it.
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APPEARANCE")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.3)
                .foregroundStyle(Theme.pink)

            HStack(spacing: 10) {
                ForEach(ThemePreference.allCases, id: \.self) { option in
                    ThemeOptionTile(option: option, isSelected: theme.preference == option) {
                        Haptics.shared.play(.tap)
                        withAnimation(.easeOut(duration: 0.2)) { theme.preference = option }
                    }
                }
            }

            Text(theme.preference == .auto
                 ? "Follows your phone's Light/Dark setting."
                 : "Always \(theme.preference.label.lowercased()) mode, whatever your phone is set to.")
                .font(Theme.Font.body(11, weight: .medium))
                .foregroundStyle(Theme.muted)
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(Theme.Font.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .tint(Theme.violet)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

/// One of the three appearance choices. Selected state uses the same
/// violet-on-violet-soft language as the dock's active tab and Ghost Mode's
/// chosen row, so it reads as "picked" without needing a checkmark.
private struct ThemeOptionTile: View {
    let option: ThemePreference
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                swatch
                HStack(spacing: 4) {
                    Image(systemName: option.symbol)
                        .font(.system(size: 10, weight: .bold))
                    Text(option.label)
                        .font(Theme.Font.body(11, weight: .heavy))
                }
                .foregroundStyle(isSelected ? Theme.violet : Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .padding(.horizontal, 8)
            .background(
                isSelected ? Theme.violetSoft : Theme.fill2,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Theme.violet : .clear, lineWidth: 2)
            )
        }
        .pressable(scale: 0.95)
    }

    /// A miniature of the map screen in the chosen palette. These are fixed
    /// literals, not `Theme` tokens — the point is to show what the *other*
    /// mode looks like while you're still in this one, so they must not
    /// adapt with the current theme.
    @ViewBuilder
    private var swatch: some View {
        switch option {
        case .light:
            ThemeSwatch(ground: 0xFFF8EF, surface: 0xFFFFFF, ink: 0x281F42)
        case .dark:
            ThemeSwatch(ground: 0x14111C, surface: 0x1E1A29, ink: 0xF5F1FA)
        case .auto:
            ZStack {
                ThemeSwatch(ground: 0xFFF8EF, surface: 0xFFFFFF, ink: 0x281F42)
                ThemeSwatch(ground: 0x14111C, surface: 0x1E1A29, ink: 0xF5F1FA)
                    .clipShape(DiagonalHalf())
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}

/// A tiny fake app screen: a ground, a floating card on it, and a friend row.
private struct ThemeSwatch: View {
    let ground: UInt32
    let surface: UInt32
    let ink: UInt32

    var body: some View {
        ZStack {
            Color(hex: ground)
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: surface))
                    .frame(height: 11)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.coral)
                        .frame(width: 9, height: 9)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(hex: ink).opacity(0.5))
                        .frame(height: 5)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
        }
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Lower-right triangle, so "Auto" reads as the two palettes split across
/// one preview — the same affordance macOS uses for its Auto appearance.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
