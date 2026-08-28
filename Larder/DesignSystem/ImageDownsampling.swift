import UIKit

/// Downsamples photo data to a fixed maximum dimension before it's ever persisted to
/// `Item.photoData`. Per the architecture review: item photos previously decoded at full camera
/// resolution, inline in the view body, uncached — a cost that compounds once list rendering is
/// lazy but still scrolls through many photographed rows. Photos are only ever displayed at
/// thumbnail size (~56pt in `StockRow`/`HubRow`, ~72pt in `ItemDetailView`), so keeping the
/// camera/photo-library's full resolution around at all serves no purpose here.
enum ImageDownsampling {
    static let maxDimension: CGFloat = 240

    /// Off the main actor: `UIImage.prepareThumbnail(of:completionHandler:)` is documented by
    /// Apple to do its work off-main, which matters here since `.onChange`/`.task` closures on a
    /// SwiftUI view run on the main actor by default — calling a *synchronous* downsampling API
    /// from one would still block it.
    static func downsample(_ data: Data) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else {
            // Already small enough — nothing to do.
            return data
        }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let thumbnail = await withCheckedContinuation { continuation in
            image.prepareThumbnail(of: targetSize) { thumbnail in
                continuation.resume(returning: thumbnail)
            }
        }
        return (thumbnail ?? image).jpegData(compressionQuality: 0.85)
    }
}
