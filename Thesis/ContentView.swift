// ContentView.swift — Thesis
// Main layout: document sidebar and the editor.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        HSplitView {
            DocumentSidebar(
                documents: documentManager.documents,
                selectedDocument: $documentManager.selectedDocument,
                onNewDocument: { documentManager.createNewDocument() },
                onRenameDocument: { documentManager.requestName(for: $0) },
                onDeleteDocument: { documentManager.deleteDocument($0) }
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            if let document = documentManager.selectedDocument {
                EditorView(document: document)
                    // A fresh editor per document object. Without this SwiftUI reuses the
                    // @StateObject engine, which would keep editing the previous document.
                    // (Object identity, not `id`: an import can replace a document in place.)
                    .id(ObjectIdentifier(document))
            } else {
                EmptyStateView(onNewDocument: { documentManager.createNewDocument() })
            }
        }
        .onChange(of: documentManager.selectedDocument) {
            documentManager.saveDocuments()
        }
        .alert(
            "Couldn't open your documents",
            isPresented: Binding(
                get: { documentManager.loadErrorMessage != nil },
                set: { if !$0 { documentManager.loadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(documentManager.loadErrorMessage ?? "")
        }
    }
}

// MARK: - Sidebar

struct DocumentSidebar: View {
    let documents: [Document]
    @Binding var selectedDocument: Document?
    let onNewDocument: () -> Void
    let onRenameDocument: (Document) -> Void
    let onDeleteDocument: (Document) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Documents").font(.headline)
                Spacer()
                Button(action: onNewDocument) { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New document (⌘N)")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List(documents) { doc in
                DocumentListItem(document: doc, isSelected: selectedDocument?.id == doc.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDocument = doc }
                    .contextMenu {
                        Button("Rename…") { onRenameDocument(doc) }
                        Menu("Export") {
                            ForEach(ExportFormat.allCases) { format in
                                Button(format.menuTitle) { Exporter.export(doc, as: format) }
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { onDeleteDocument(doc) }
                    }
            }
            .listStyle(.sidebar)
        }
    }
}

struct DocumentListItem: View {
    @ObservedObject var document: Document
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(document.title.isEmpty ? "Untitled" : document.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if document.hasUnsnapshottedChanges {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                        .help("Changes since the last snapshot")
                }
            }
            HStack {
                Text(document.latestNamedSnapshot?.name ?? "No named snapshot")
                    .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                Text(document.lastModified, style: .relative)
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let onNewDocument: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.cursor").font(.system(size: 64)).foregroundColor(.secondary)
            Text("No Document Selected").font(.title2).foregroundColor(.secondary)
            Text("Create a document or pick one from the sidebar.")
                .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button(action: onNewDocument) {
                Label("New Document", systemImage: "plus.circle.fill").font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
