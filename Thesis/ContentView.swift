// ContentView.swift — Thesis
// Main layout: sidebar, editor, history panel

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @State private var showingHistory = false
    
    var body: some View {
        HSplitView {
            DocumentSidebar(
                documents: documentManager.documents,
                selectedDocument: $documentManager.selectedDocument,
                onNewDocument: { documentManager.createNewDocument() },
                onDeleteDocument: { doc in documentManager.deleteDocument(doc) }
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            
            if let document = documentManager.selectedDocument {
                EditorContainer(
                    document: document,
                    showingHistory: $showingHistory,
                    onSave: { documentManager.saveDocuments() }
                )
            } else {
                EmptyStateView(onNewDocument: { documentManager.createNewDocument() })
            }
        }
        .onChange(of: documentManager.selectedDocument) {
            documentManager.saveDocuments()
        }
    }
}

// MARK: - Document Sidebar

struct DocumentSidebar: View {
    let documents: [Document]
    @Binding var selectedDocument: Document?
    let onNewDocument: () -> Void
    let onDeleteDocument: (Document) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Thoughts").font(.headline)
                Spacer()
                Button(action: onNewDocument) { Image(systemName: "plus") }
                    .buttonStyle(.borderless).keyboardShortcut("n", modifiers: [.command])
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            List(documents) { doc in
                DocumentListItem(document: doc, isSelected: selectedDocument?.id == doc.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDocument = doc }
                    .contextMenu {
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
                Text(document.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                if document.hasUnsavedChanges {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                }
                if document.branches.count > 1 {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9)).foregroundColor(.purple)
                }
            }
            HStack {
                if let latest = document.currentBranchHead {
                    Text(latest.name).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                } else {
                    Text("No draft").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Text(document.lastModified, style: .relative)
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Editor Container

struct EditorContainer: View {
    @ObservedObject var document: Document
    @Binding var showingHistory: Bool
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Thought title", text: $document.title)
                    .textFieldStyle(.plain).font(.title2).padding()
                Spacer()
                Button(action: { showingHistory.toggle() }) {
                    Label(showingHistory ? "Hide Panel" : "Evolution",
                          systemImage: showingHistory ? "sidebar.right" : "clock")
                }
                .buttonStyle(.borderless).padding(.trailing)
                .keyboardShortcut("e", modifiers: [.command])
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            HSplitView {
                ModalEditor(document: .constant(document))
                    .frame(minWidth: 500)
                
                if showingHistory {
                    DraftHistoryView(
                        document: document,
                        onRestore: { draft in
                            document.restoreDraft(draft)
                            onSave()
                        },
                        onNavigateToAnnotation: { annotation in
                            // Navigation would scroll the editor to the annotation's position
                            // For now this is wired through as a callback
                        },
                        onClose: { showingHistory = false }
                    )
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)
                }
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let onNewDocument: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.cursor").font(.system(size: 64)).foregroundColor(.secondary)
            Text("No Thought Selected").font(.title2).foregroundColor(.secondary)
            Text("Create a new thought or select one from the sidebar.")
                .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button(action: onNewDocument) {
                Label("New Thought", systemImage: "plus.circle.fill").font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Color Helper

func colorForSemanticType(_ name: String) -> Color {
    switch name {
    case "green":  return .green
    case "red":    return .red
    case "orange": return .orange
    case "blue":   return .blue
    case "purple": return .purple
    case "yellow": return .yellow
    default:       return .primary
    }
}
