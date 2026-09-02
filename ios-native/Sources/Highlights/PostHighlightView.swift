import PhotosUI
import SwiftUI

/// The story composer — port of the web app's `PostHighlightSheet`. A photo
/// isn't required; a text-only highlight still posts as a card. Attaching
/// location is opt-in and off by default — the same privacy instinct as
/// Ghost Mode: a story pin on the map is a bigger disclosure than a story in
/// the rail.
struct PostHighlightView: View {
    let fix: Fix?
    var onPosted: () -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var caption = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var attachLocation = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                VStack(spacing: 18) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Group {
                            if let image {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill").font(.system(size: 26))
                                    Text("Choose a photo (optional)").font(Theme.Font.body(12, weight: .semibold))
                                }
                                .foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .background(Color(hex: 0xF4F0F6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .onChange(of: pickerItem) { _, item in
                        Task {
                            guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                            image = UIImage(data: data)
                        }
                    }

                    TextField("What are you up to?", text: $caption)
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .tint(Theme.violet)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        attachLocation.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Attach my location").font(Theme.Font.body(13, weight: .bold))
                                Text(fix == nil ? "No location right now" : "Friends will see where this was posted")
                                    .font(Theme.Font.body(10, weight: .medium))
                            }
                            Spacer()
                            Image(systemName: attachLocation ? "checkmark.circle.fill" : "circle")
                        }
                        .foregroundStyle(attachLocation ? Theme.violet : Theme.ink)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(fix == nil)

                    Text("Disappears after 24 hours, visible to friends only")
                        .font(Theme.Font.body(10, weight: .medium))
                        .foregroundStyle(Theme.muted)

                    if let message {
                        Text(message).font(Theme.Font.body(11, weight: .medium)).foregroundStyle(Theme.coral)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(busy ? "Posting…" : "Post ✨")
                            .font(Theme.Font.body(15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(busy)
                    .pressable()

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Post a story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.Font.body(14, weight: .bold))
                }
            }
        }
    }

    private func submit() async {
        guard let userId = auth.profile?.id else { return }
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard image != nil || !text.isEmpty else {
            message = "Take a photo or write something"
            return
        }
        busy = true
        message = nil
        defer { busy = false }
        do {
            var mediaUrl: String?
            if let image {
                mediaUrl = try await HighlightsService.uploadPhoto(userId: userId, image: image)
            }
            let coordinate = (attachLocation ? fix : nil).map { (lat: $0.lat, lng: $0.lng) }
            try await HighlightsService.post(userId: userId, body: text, mediaUrl: mediaUrl, coordinate: coordinate)
            onPosted()
            dismiss()
        } catch {
            message = "Couldn't post that — try again."
        }
    }
}
