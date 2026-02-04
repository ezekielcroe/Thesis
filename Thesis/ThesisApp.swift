import SwiftUI

@main
struct ThesisApp: App {
    @StateObject private var documentManager = DocumentManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thought") {
                    documentManager.createNewDocument()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
