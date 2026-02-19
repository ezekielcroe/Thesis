// ThesisApp.swift — Thesis
// Application entry point

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
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thought") { documentManager.createNewDocument() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Documents") { documentManager.saveDocuments() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
