import SwiftUI

@main
struct ReppApp: App {
    @State private var model = AppModel()
    @State private var screenTime = ScreenTimeManager()
    @State private var store = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(screenTime)
                .environment(store)
                .tint(Palette.green)
        }
    }
}
