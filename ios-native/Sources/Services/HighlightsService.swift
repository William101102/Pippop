import Foundation
import Supabase
import UIKit

/// A 24-hour-expiring photo/text post — à la Zenly/Snap "highlights". Port
/// of the web app's `services/highlights.ts`.
struct Highlight: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    var body: String
    var mediaUrl: String?
    let createdAt: Date
    let expiresAt: Date
    var lat: Double?
    var lng: Double?
}

enum HighlightsService {
    private static let maxPhotoDimension: CGFloat = 960

    /// Still-live highlights from me and my accepted friends, newest first,
    /// grouped by author. RLS grants the owner unconditional (no-expiry)
    /// access to their own rows, so this filters by `expiresAt` explicitly
    /// for everyone — including "me" — the same guard the web client
    /// applies, so your own story ring doesn't read as "live" forever off
    /// its first-ever post.
    static func loadFriendHighlights() async throws -> [UUID: [Highlight]] {
        let rows: [Highlight] = try await Backend.client
            .from("highlights")
            .select()
            .gt("expires_at", value: Date.now)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
        var byUser: [UUID: [Highlight]] = [:]
        for row in rows { byUser[row.userId, default: []].append(row) }
        return byUser
    }

    @discardableResult
    static func post(userId: UUID, body: String, mediaUrl: String?, coordinate: (lat: Double, lng: Double)?) async throws -> Highlight {
        struct NewHighlight: Encodable {
            let userId: UUID
            let body: String
            let mediaUrl: String?
            let lat: Double?
            let lng: Double?
        }
        return try await Backend.client
            .from("highlights")
            .insert(NewHighlight(
                userId: userId,
                body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                mediaUrl: mediaUrl,
                lat: coordinate?.lat,
                lng: coordinate?.lng
            ))
            .select()
            .single()
            .execute()
            .value
    }

    static func delete(_ id: UUID) async throws {
        try await Backend.client.from("highlights").delete().eq("id", value: id).execute()
    }

    /// Downscales to a manageable JPEG before upload, same reasoning as the
    /// web app's canvas resize: a full-res phone photo shouldn't blow past
    /// upload limits or take forever on a mobile connection.
    static func uploadPhoto(userId: UUID, image: UIImage) async throws -> String {
        let scale = min(1, maxPhotoDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: targetSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = resized.jpegData(compressionQuality: 0.86) else {
            throw HighlightError.badImage
        }

        // Reuses the `avatars` storage bucket — its policy only checks that
        // the first path segment is the uploader's own uid, so any filename
        // under that folder works; no new bucket/policy needed.
        //
        // The folder MUST be lowercase: that policy compares against
        // `auth.uid()::text`, which Postgres renders lowercase, while Swift's
        // `"\(uuid)"` is UPPERCASE. Interpolating the UUID directly made every
        // photo upload fail RLS — see `ProfileService.storageFolder`.
        let path = "\(ProfileService.storageFolder(for: userId))/highlight-\(Int(Date.now.timeIntervalSince1970 * 1000)).jpg"
        try await Backend.client.storage.from("avatars").upload(path, data: data, options: .init(contentType: "image/jpeg"))
        return try Backend.client.storage.from("avatars").getPublicURL(path: path).absoluteString
    }
}

enum HighlightError: LocalizedError {
    case badImage
    var errorDescription: String? { "Couldn't read that photo — try another one" }
}
