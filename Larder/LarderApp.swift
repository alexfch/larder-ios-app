import SwiftUI
import SwiftData

@main
struct LarderApp: App {
    let modelContainer: ModelContainer = Self.makeModelContainer()

    @State private var toastCenter = ToastCenter()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(toastCenter)
                .overlay(ToastOverlay(message: toastCenter.message))
                // The design system (Color.larderBackground etc.) is light-only for now;
                // lock appearance so Form-based screens don't flip to a native dark look
                // that clashes with the rest of the app. Revisit if real Dark Mode support
                // gets built later.
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }

    /// Builds the app's `ModelContainer`, recovering from a corrupted or otherwise unopenable
    /// store instead of crash-looping on every launch. `try!` here used to mean any store
    /// problem — a corrupted SQLite file, a disk error, a schema SwiftData can't reconcile — was
    /// unrecoverable: the app would crash in `init`, before any UI (or even a crash-reporting
    /// screen) could show, every single time it launched. Now a failed open resets the store and
    /// retries once with a fresh, empty one; only if that second attempt also fails — meaning the
    /// problem isn't the store's contents at all, e.g. a full disk or a permissions failure — does
    /// this still terminate, since there is genuinely no usable container to hand back.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self])
        let configuration = ModelConfiguration(schema: schema)

        applyFileProtection(to: configuration)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            assertionFailure("ModelContainer failed to load, resetting the store: \(error)")
            resetStore(at: configuration.url)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("ModelContainer still couldn't be created after resetting the store: \(error)")
            }
        }
    }

    /// Moves the store aside — the SQLite main file plus its `-wal`/`-shm` sidecar files — rather
    /// than deleting it outright, so a corrupted store can still be pulled off the device for a
    /// postmortem instead of being silently destroyed.
    private static func resetStore(at url: URL) {
        let fileManager = FileManager.default
        let timestamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: url.path + suffix + ".corrupted-\(timestamp)")
            try? fileManager.moveItem(at: source, to: destination)
        }
    }

    /// Explicit `NSFileProtectionKey` on the store's containing directory, so sidecar files
    /// (`-wal`/`-shm`, written after the first insert) inherit it too. This app's data — pantry
    /// contents and optional item photos — isn't highly sensitive, but leaving protection
    /// implicit was flagged by the architecture review. `.completeUntilFirstUserAuthentication`
    /// keeps the store unreadable before the device's first unlock after boot while still
    /// allowing this foreground-only app to read/write normally once unlocked, without the
    /// stricter `.complete` class's risk of locking the store mid-session if the device
    /// auto-locks while the app is suspended in the background.
    private static func applyFileProtection(to configuration: ModelConfiguration) {
        let directory = configuration.url.deletingLastPathComponent()
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
    }
}
