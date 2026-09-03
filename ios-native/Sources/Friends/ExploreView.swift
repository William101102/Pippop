import CoreLocation
import SwiftUI

/// The Explore tab — adding people, both directions.
///
/// Sharing your own link only needs your username, which is already on
/// `auth.profile` — safe to ship.
///
/// Sending goes through `FriendsService.sendRequest`, which writes a
/// `friendships` row with `status: "pending"` — never `"accepted"` directly
/// — and now checked against the real schema in
/// `backend/supabase/setup.sql` (`requester_id`/`addressee_id`, not the
/// `user_id`/`friend_id` this used to (wrongly) insert). The recipient sees
/// it and can accept/decline from the Friends tab's request inbox or the
/// notifications bell — both now wired up.
///
/// Also carries the "Nearby" section (closest friends + nearby check-ins +
/// the check-in button) — port of the web app's `NearbyPanel`, which lives
/// under its own "探索/Explore" dock icon on the web too, so this is the
/// same screen doing the same two jobs web splits only by scroll position.
struct ExploreView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var usernameToAdd = ""
    @State private var notice: String?
    @State private var sending = false

    @State private var nearbyFriends: [(friend: Friend, meters: Double)] = []
    @State private var nearbyPlaces: [NearbyPlace] = []
    @State private var loadingNearby = true
    @State private var showCheckIn = false

    private var myInviteURL: URL? {
        guard let username = auth.profile?.username else { return nil }
        return URL(string: "pinpop://add/\(username)")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        shareCard
                        addCard
                        nearbyCard

                        if let notice {
                            Text(notice)
                                .font(Theme.Font.body(12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Font.body(14, weight: .bold))
                }
            }
        }
        .onAppear {
            // Arrived here from a `pinpop://add/<username>` link — prefill it.
            if case let .addFriend(username) = DeepLink.shared.pending {
                usernameToAdd = username
                DeepLink.shared.pending = nil
            }
        }
        .task { await loadNearby() }
        .sheet(isPresented: $showCheckIn) {
            if let fix = location.current {
                CheckInView(fix: fix) { Task { await loadNearby() } }
            }
        }
    }

    /// Port of the web app's `NearbyPanel` — closest friends first, then
    /// nearby check-ins, plus the "Check in here" button.
    private var nearbyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEARBY")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.3)
                .foregroundStyle(Theme.pink)

            Button {
                showCheckIn = true
            } label: {
                Label("Check in here", systemImage: "mappin.circle.fill")
                    .font(Theme.Font.body(14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(location.current == nil)
            .pressable()

            if location.current == nil {
                Text("Turn on location to see nearby people and places.")
                    .font(Theme.Font.body(11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            } else if loadingNearby {
                ProgressView().tint(Theme.violet).frame(maxWidth: .infinity)
            } else {
                if !nearbyFriends.isEmpty {
                    Text("Closest friends")
                        .font(Theme.Font.body(11, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                    ForEach(nearbyFriends, id: \.friend.id) { entry in
                        HStack(spacing: 10) {
                            AvatarView(profile: entry.friend.profile, size: 38)
                            Text(entry.friend.displayName)
                                .font(Theme.Font.body(13, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(distanceLabel(entry.meters))
                                .font(Theme.Font.body(11, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !nearbyPlaces.isEmpty {
                    Text("Nearby places")
                        .font(Theme.Font.body(11, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, nearbyFriends.isEmpty ? 0 : 6)
                    ForEach(nearbyPlaces) { entry in
                        HStack(spacing: 10) {
                            Text(entry.place.category.icon).font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.place.name)
                                    .font(Theme.Font.body(13, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                if let address = entry.place.address {
                                    Text(address).font(Theme.Font.body(10, weight: .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(distanceLabel(entry.distanceMeters))
                                .font(Theme.Font.body(11, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
                if nearbyFriends.isEmpty && nearbyPlaces.isEmpty {
                    Text("Nothing nearby yet.")
                        .font(Theme.Font.body(11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(16)
        .floatingCard(radius: 24)
    }

    private func distanceLabel(_ meters: Double) -> String {
        meters < 1000 ? String(format: "%.0f m", meters) : String(format: "%.1f km", meters / 1000)
    }

    private func loadNearby() async {
        guard let fix = location.current, let meId = auth.profile?.id else {
            loadingNearby = false
            return
        }
        loadingNearby = nearbyFriends.isEmpty && nearbyPlaces.isEmpty
        let friends = (try? await FriendsService.load(for: meId)) ?? []
        let origin = CLLocation(latitude: fix.lat, longitude: fix.lng)
        nearbyFriends = friends
            .compactMap { friend -> (friend: Friend, meters: Double)? in
                guard let loc = friend.location else { return nil }
                return (friend, origin.distance(from: CLLocation(latitude: loc.lat, longitude: loc.lng)))
            }
            .sorted { $0.meters < $1.meters }
        nearbyPlaces = (try? await CheckInsService.loadNearbyPlaces(lat: fix.lat, lng: fix.lng)) ?? []
        loadingNearby = false
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR INVITE LINK")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.3)
                .foregroundStyle(Theme.pink)

            if let profile = auth.profile {
                HStack(spacing: 12) {
                    AvatarView(profile: profile, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(Theme.Font.body(14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("@\(profile.username)")
                            .font(Theme.Font.body(11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }

                if let url = myInviteURL {
                    ShareLink(item: url) {
                        Label("Share invite link", systemImage: "square.and.arrow.up")
                            .font(Theme.Font.body(14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .pressable()
                }
            }
        }
        .padding(16)
        .floatingCard(radius: 24)
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD SOMEONE")
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.3)
                .foregroundStyle(Theme.pink)

            HStack(spacing: 10) {
                Text("@")
                    .font(Theme.Font.body(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
                TextField("username", text: $usernameToAdd)
                    .font(Theme.Font.body(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.violet)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Task { await sendRequest(username: usernameToAdd) }
            } label: {
                Text(sending ? "Sending…" : "Add friend")
                    .font(Theme.Font.body(14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.ink.opacity(0.12), lineWidth: 1)
                    )
            }
            .disabled(sending || usernameToAdd.trimmingCharacters(in: .whitespaces).count < 3)
            .pressable()
        }
        .padding(16)
        .floatingCard(radius: 24)
    }

    private func sendRequest(username: String) async {
        guard let me = auth.profile else { return }
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard handle.count >= 3 else { return }

        sending = true
        defer { sending = false }

        do {
            struct Match: Decodable { let id: UUID }
            let matches: [Match] = try await Backend.client
                .from("profiles")
                .select("id")
                .eq("username", value: handle)
                .limit(1)
                .execute()
                .value

            guard let friendId = matches.first?.id else {
                notice = "No one goes by @\(handle)."
                return
            }
            guard friendId != me.id else {
                notice = "That's you."
                return
            }

            // `FriendsService.sendRequest` also handles the case where
            // `handle` already invited *me* first — it accepts theirs
            // instead of creating a second, conflicting row.
            let result = try await FriendsService.sendRequest(from: me.id, to: friendId)
            switch result {
            case "already_friends": notice = "You're already friends with @\(handle)."
            case "already_sent": notice = "You already sent @\(handle) a request."
            case "accepted": notice = "@\(handle) had already added you — you're friends now 🎉"
            default: notice = "Request sent to @\(handle)."
            }
            usernameToAdd = ""
        } catch {
            notice = "Couldn't send that — try again."
        }
    }
}
