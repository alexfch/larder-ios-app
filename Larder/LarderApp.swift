import SwiftUI
import SwiftData

@main
struct LarderApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([Item.self, Lot.self, Transaction.self, CountSession.self, CountLine.self])
        let configuration = ModelConfiguration(schema: schema)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

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
}
