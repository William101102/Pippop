import Foundation
import Supabase
import UIKit

/// Avatar photos — the native port of the web app's `src/services/profile.ts`.
///
/// This is what was missing: `AvatarView` could already *render* an
/// `avatar_url`, but nothing in the native build could ever *set* one, so
/// every account created on iOS was stuck showing its initial forever.
enum ProfileService {
    /// An avatar is displayed at 86pt at most, so there's no reason to ship a
    /// 12-megapixel camera roll original to storage.
    private static let maxDimension: CGFloat = 512
    /// Matches the bucket's own `file_size_limit` in `setup.sql`.
    private static let maxUploadBytes = 12 * 1024 * 1024

    /// The storage folder a user is allowed to write to.
    ///
    /// **This has to be lowercase.** The bucket policy is
    /// `(storage.foldername(name))[1] = auth.uid()::text`, and Postgres
    /// renders a uuid in lowercase — while Swift's `UUID.uuidString` (and so
    /// `"\(uuid)"`) is UPPERCASE. Interpolating the UUID directly builds a
    /// path like `E621E1F8-…/avatar.jpg`, the policy compares it against
    /// `e621e1f8-…`, and every single upload is rejected by RLS. That was the
    /// "Upload failed" — nothing to do with the connection.
    static func storageFolder(for userId: UUID) -> String {
        userId.uuidString.lowercased()
    }

    /// Resizes, uploads to `avatars/<uid>/avatar-<ms>.jpg`, then points
    /// `profiles.avatar_url` at the public URL — the same order, the same
    /// path shape and the same `upsert: true` the web app uses, so a photo
    /// set on either client shows up on both.
    @discardableResult
    static func uploadAvatar(userId: UUID, image: UIImage) async throws -> String {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: targetSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = resized.jpegData(compressionQuality: 0.86) else {
            throw AvatarError.badImage
        }
        guard data.count <= maxUploadBytes else { throw AvatarError.tooLarge }

        let path = "\(storageFolder(for: userId))/avatar-\(Int(Date.now.timeIntervalSince1970 * 1000)).jpg"
        do {
            try await Backend.client.storage
                .from("avatars")
                .upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
        } catch {
            // Carry the real reason through. Swallowing it behind "check your
            // connection" is what made the RLS rejection above so hard to see.
            throw AvatarError.uploadFailed(String(describing: error))
        }

        let publicURL = try Backend.client.storage
            .from("avatars")
            .getPublicURL(path: path)
            .absoluteString

        struct Update: Encodable { let avatarUrl: String }
        do {
            try await Backend.client
                .from("profiles")
                .update(Update(avatarUrl: publicURL))
                .eq("id", value: userId)
                .execute()
        } catch {
            // Don't leave an orphaned object behind if the row update fails —
            // the web app rolls the upload back the same way.
            _ = try? await Backend.client.storage.from("avatars").remove(paths: [path])
            throw AvatarError.saveFailed(String(describing: error))
        }

        return publicURL
    }
}

enum AvatarError: LocalizedError {
    case badImage
    case tooLarge
    case uploadFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .badImage: "Couldn't read that photo — try another one"
        case .tooLarge: "That photo is too big — pick a smaller one"
        case let .uploadFailed(detail): "Upload failed — \(detail)"
        case let .saveFailed(detail): "Uploaded, but couldn't save it to your profile — \(detail)"
        }
    }
}
