import Foundation
import FirebaseStorage

/// Uploads and fetches item photos in Cloud Storage for Firebase (Phase 2 — see `storage.rules`
/// and `Item.photoStorageRef`). One object per item at a fixed path, so replacing a photo is
/// always a plain overwrite of the same object — no orphaned files to clean up, no delete flow
/// needed yet.
enum PhotoStorage {
    private static let storage = Storage.storage()

    static func path(householdId: String, itemId: String) -> String {
        "households/\(householdId)/items/\(itemId)"
    }

    /// Uploads already-downsampled photo data (see `ImageDownsampling`) and returns the storage
    /// path to persist as `Item.photoStorageRef`. Declares `image/jpeg` unconditionally: the
    /// overwhelming majority of photos reach here via `ImageDownsampling`'s resize branch, which
    /// always re-encodes to JPEG; the rare already-small photo-library pick that skips resizing
    /// keeps its original bytes, but `UIImage(data:)` (used everywhere a photo gets displayed)
    /// sniffs the real format from the bytes themselves, not this declared header, so a slightly
    /// inaccurate label here has no functional effect.
    @discardableResult
    static func upload(_ data: Data, householdId: String, itemId: String) async throws -> String {
        let objectPath = path(householdId: householdId, itemId: itemId)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await storage.reference(withPath: objectPath).putDataAsync(data, metadata: metadata)
        return objectPath
    }

    /// Fetches the raw bytes for a previously-uploaded photo. `maxSize` is a hard ceiling on what
    /// the SDK will download — `storage.rules` already caps uploads at 5 MiB; this mirrors that
    /// rather than trusting an object to be small just because the app itself always uploads
    /// downsampled data.
    static func fetch(storageRef: String, maxSize: Int64 = 5 * 1024 * 1024) async throws -> Data {
        try await storage.reference(withPath: storageRef).data(maxSize: maxSize)
    }
}
