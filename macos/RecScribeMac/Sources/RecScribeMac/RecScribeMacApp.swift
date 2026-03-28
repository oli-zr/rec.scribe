import SwiftUI

@main
struct RecScribeMacApp: App {
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionStore)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    sessionStore.load()
                }
        }
        .defaultSize(width: 1100, height: 720)
    }
}
