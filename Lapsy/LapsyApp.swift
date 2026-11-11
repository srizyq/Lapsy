import SwiftUI

@main
struct LapsyApp: App {
    init() {
        FontRegistration.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
