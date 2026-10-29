import SwiftUI

@main
struct NODOApp: App {
    @StateObject private var store = DeviceStore()
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(store)

        }
    }
}
