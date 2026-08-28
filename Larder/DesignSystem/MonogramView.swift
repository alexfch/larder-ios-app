import SwiftUI
import UIKit

/// Process-lifetime cache of decoded thumbnails, keyed by the photo data itself rather than the
/// item's id — so a changed photo naturally misses the cache instead of needing explicit
/// invalidation, and unrelated `ItemThumbnail` instances (list row vs. detail view) share one
/// decode. `Item.photoData` is downsampled at capture time (see `ImageDownsampling`), so what
/// this avoids is redundant *decode* work on every row re-render, not a large decode to begin with.
private let thumbnailCache = NSCache<NSString, UIImage>()

/// Photo thumbnail for an item; falls back to a monogram square when no photo is set,
/// per FR-3.2's acceptance criteria.
struct ItemThumbnail: View {
    let photoData: Data?
    let monogram: String
    var size: CGFloat = 56

    private var cachedImage: UIImage? {
        guard let photoData else { return nil }
        let key = "\(photoData.hashValue)" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let decoded = UIImage(data: photoData) else { return nil }
        thumbnailCache.setObject(decoded, forKey: key)
        return decoded
    }

    var body: some View {
        Group {
            if let cachedImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.larderMonogramDark
                    Text(monogram)
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}
