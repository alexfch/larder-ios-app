import SwiftUI
import UIKit

/// Process-lifetime cache of decoded thumbnails, keyed by `photoStorageRef` for remote photos or
/// the local `Data`'s hash for an in-progress capture — bounded on both entry count and total
/// byte cost. A bare, unbounded `NSCache()` was fine when every entry came from a small,
/// already-downsampled local `Data` blob; it stopped being safe the moment entries could also
/// arrive from an uncontrolled-size remote fetch (Cloud Storage, Phase 2).
private let thumbnailCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 200
    cache.totalCostLimit = 50 * 1024 * 1024 // ~50 MiB of decoded bitmap data
    return cache
}()

/// Photo thumbnail for an item; falls back to a monogram square when no photo is set, per FR-3.2's
/// acceptance criteria. Two photo sources, checked in this order:
/// - `photoData`: already-in-memory bytes, for the New Product form's live preview before
///   anything's been uploaded (the item doesn't exist yet, so there's no `photoStorageRef` at all).
/// - `photoStorageRef`: triggers an async Cloud Storage fetch (`PhotoStorage.fetch`), cached by
///   that ref so scrolling back to an already-loaded row is instant, not a re-fetch.
/// A saved item has one or the other, not both, in practice.
struct ItemThumbnail: View {
    let photoData: Data?
    var photoStorageRef: String? = nil
    let monogram: String
    var size: CGFloat = 56
    /// Which `larderMono*` tile tone to fall back to when there's no photo -- defaults to the
    /// single tone every thumbnail used before the redesign's four-tone rotation. Callers that
    /// want that rotation (e.g. `CheckOutRow`) pass a per-item tone computed from the item's id.
    var monogramBackground: Color = .larderMono1

    @State private var remoteImage: UIImage?

    private var localImage: UIImage? {
        guard let photoData else { return nil }
        let key = "\(photoData.hashValue)" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let decoded = UIImage(data: photoData) else { return nil }
        thumbnailCache.setObject(decoded, forKey: key, cost: photoData.count)
        return decoded
    }

    var body: some View {
        Group {
            if let image = localImage ?? remoteImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    monogramBackground
                    Text(monogram)
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(Color.larderMonoForeground)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        // Keyed on `photoStorageRef` so SwiftUI cancels and restarts this automatically when a
        // row's underlying item changes (e.g. a recycled row in a `LazyVStack`) or the ref itself
        // changes -- exactly the "per-row fetch cancellation" the architecture review called for,
        // with no manual bookkeeping.
        .task(id: photoStorageRef) {
            await loadRemoteIfNeeded()
        }
    }

    private func loadRemoteIfNeeded() async {
        remoteImage = nil
        // A local in-progress capture always wins (see `localImage`) -- no remote ref exists yet
        // for an item that hasn't been saved.
        guard photoData == nil, let photoStorageRef else { return }

        let key = photoStorageRef as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            remoteImage = cached
            return
        }
        guard let data = try? await PhotoStorage.fetch(storageRef: photoStorageRef),
              let decoded = UIImage(data: data) else { return }
        guard !Task.isCancelled else { return }
        thumbnailCache.setObject(decoded, forKey: key, cost: data.count)
        remoteImage = decoded
    }
}
