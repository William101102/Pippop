import SwiftUI

/// A process-wide memory cache for avatar photos.
///
/// `AsyncImage` reloads whenever its view is rebuilt, and falls back to its
/// placeholder while it does. The map pin is rebuilt on **every location
/// fix**, so a moving person's own avatar was flickering back to the coral
/// initial several times a minute — which is what "the orange background
/// shows through while I'm moving" actually was. URLCache doesn't help: it
/// saves the download, not the decode, and not the view state.
///
/// `NSCache` is thread-safe, so the synchronous lookup is `nonisolated` and a
/// cache hit renders on the very first frame with no placeholder at all.
final class AvatarImageCache: @unchecked Sendable {
    static let shared = AvatarImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        // Avatars are small and there are only ever a handful of friends on
        // screen; this is a ceiling against pathology, not a working limit.
        cache.countLimit = 120
    }

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        guard
            let (data, _) = try? await URLSession.shared.data(from: url),
            let image = UIImage(data: data)
        else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Draws a cached avatar photo, filling its container completely.
///
/// The `frame` + `clipped` pair is the other half of the bug: `scaledToFill`
/// on its own lets the image lay out at whatever size its own aspect ratio
/// asks for, so a non-square photo could sit slightly off-centre inside the
/// circle and leave a sliver of the tint behind it showing. Pinning it to the
/// avatar's exact square first means there is nothing left to show through.
struct AvatarImage: View {
    let url: URL
    let size: CGFloat

    @State private var loaded: UIImage?

    private var image: UIImage? { loaded ?? AvatarImageCache.shared.cached(url) }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                // Nothing — the caller's tint and initial stay visible until
                // the photo is in hand, which is the one moment they should.
                Color.clear
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            loaded = await AvatarImageCache.shared.load(url)
        }
    }
}
