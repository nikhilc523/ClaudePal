import SwiftUI
import ClaudePalKit

@main
struct ClaudePalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task {
                    await model.bootstrap()
                }
        }
    }
}
