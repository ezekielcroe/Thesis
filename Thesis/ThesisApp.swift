// ThesisApp.swift — Thesis
// Application entry point

import SwiftUI
import AppKit

/// Receives .thesis files opened from Finder: double-click, Open With, or dropped on the
/// Dock icon. This also works on a cold launch, before any window exists.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        // Let launch finish (and the window appear) before showing any import prompts.
        Task { @MainActor in Exporter.open(urls, into: DocumentManager.shared) }
    }
}

@main
struct ThesisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var documentManager = DocumentManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentManager)
                .frame(minWidth: 900, minHeight: 600)
                // If SwiftUI routes an opened file to the window instead of the delegate,
                // import it here (Exporter.open ignores the same file arriving twice).
                .onOpenURL { url in Exporter.open([url], into: documentManager) }
                // Use the open window for opened files rather than spawning another;
                // SwiftUI only opens a new window if none is open.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document") { documentManager.createNewDocument() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Rename Document…") {
                    if let doc = documentManager.selectedDocument { documentManager.requestName(for: doc) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(documentManager.selectedDocument == nil)
            }
            CommandGroup(replacing: .importExport) {
                Menu("Export") {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.menuTitle) {
                            if let doc = documentManager.selectedDocument { Exporter.export(doc, as: format) }
                        }
                    }
                }
                .disabled(documentManager.selectedDocument == nil)
                Button("Back Up All Documents…") { Exporter.backUpAll(documentManager.documents) }
                    .disabled(documentManager.documents.isEmpty)
                Divider()
                Button("Import Archive…") {
                    if let imported = Exporter.chooseArchive() {
                        documentManager.importDocuments(imported, resolve: Exporter.askAboutConflict)
                    }
                }
            }
            // Documents save themselves; ⌘S belongs to the editor (review + named snapshot).
            CommandGroup(replacing: .saveItem) {}
        }

        Settings {
            SettingsView()
        }
    }
}
