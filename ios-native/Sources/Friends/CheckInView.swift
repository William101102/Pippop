import SwiftUI

/// The check-in sheet — port of the web app's `CheckInPanel`.
struct CheckInView: View {
    let fix: Fix
    var onDone: () -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address: String?
    @State private var category: PlaceCategory = .cafe
    @State private var visibility: VisitVisibility = .friends
    @State private var note = ""
    @State private var resolving = true
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        field("Place name", text: $name, placeholder: resolving ? "Finding nearby places…" : "e.g. the cafe downstairs")
                        if let address, !resolving {
                            Text(address)
                                .font(Theme.Font.body(11, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }

                        Text("CATEGORY")
                            .font(Theme.Font.body(10, weight: .heavy))
                            .kerning(1.1)
                            .foregroundStyle(Theme.pink)
                        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: 10) {
                            ForEach(PlaceCategory.allCases, id: \.self) { item in
                                Button {
                                    category = item
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(item.icon).font(.system(size: 20))
                                        Text(item.label).font(Theme.Font.body(9, weight: .bold))
                                    }
                                    .foregroundStyle(category == item ? .white : Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .background(
                                        category == item ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color(hex: 0xF4F0F6)),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                }
                            }
                        }

                        field("Say something (optional)", text: $note, placeholder: "The latte here is great")

                        Text("WHO CAN SEE THIS")
                            .font(Theme.Font.body(10, weight: .heavy))
                            .kerning(1.1)
                            .foregroundStyle(Theme.pink)
                        ForEach(VisitVisibility.allCases, id: \.self) { item in
                            Button {
                                visibility = item
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label).font(Theme.Font.body(13, weight: .bold)).foregroundStyle(Theme.ink)
                                        Text(item.detail).font(Theme.Font.body(11, weight: .medium)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: visibility == item ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(visibility == item ? Theme.violet : Theme.muted)
                                }
                                .padding(12)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        if let message {
                            Text(message).font(Theme.Font.body(11, weight: .medium)).foregroundStyle(Theme.coral)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Text(busy ? "Checking in…" : "Check in 📍")
                                .font(Theme.Font.body(15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .pressable()
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Where are you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.Font.body(14, weight: .bold))
                }
            }
        }
        .task {
            let result = await CheckInsService.reverseGeocode(lat: fix.lat, lng: fix.lng)
            if name.isEmpty, let suggested = result.name { name = suggested }
            address = result.address
            resolving = false
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.Font.body(10, weight: .heavy))
                .kerning(1.1)
                .foregroundStyle(Theme.pink)
            TextField(placeholder, text: text)
                .font(Theme.Font.body(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .tint(Theme.violet)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func submit() async {
        guard let userId = auth.profile?.id else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await CheckInsService.checkIn(
                userId: userId, name: name, category: category, lat: fix.lat, lng: fix.lng,
                address: address, visibility: visibility, note: note
            )
            onDone()
            dismiss()
        } catch {
            message = "Couldn't check in — try again."
        }
    }
}
