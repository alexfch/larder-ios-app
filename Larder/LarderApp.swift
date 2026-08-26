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
        }
        .modelContainer(modelContainer)
    }
}
