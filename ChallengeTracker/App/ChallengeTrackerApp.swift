import SwiftUI

@main
struct ChallengeTrackerApp: App {
    init() {
        PixelFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
