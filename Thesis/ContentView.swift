import SwiftUI

struct ContentView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @State private var showingHistory = false
    
    var body: some View {
        HSplitView {
            // Sidebar - Document list
            DocumentSidebar(
                documents: documentManager.documents,
                selectedDocument: $documentManager.selectedDocument,
                onNewDocument: {
                    documentManager.createNewDocument()
                },
                onDeleteDocument: { doc in
                    documentManager.deleteDocument(doc)
                }
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            
            // Main editor area
            if let document = documentManager.selectedDocument {
                EditorContainer(
                    document: document,
                    showingHistory: $showingHistory,
                    onSave: {
                        documentManager.saveDocuments()
                    }
                )
            } else {
                EmptyStateView(
                    onNewDocument: {
                        documentManager.createNewDocument()
                    }
                )
            }
        }
        // FIX: Updated onChange syntax for macOS 14+
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
            // Header
            HStack {
                Text("Thoughts")
                    .font(.headline)
                Spacer()
                Button(action: onNewDocument) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Document list
            List(documents) { doc in
                DocumentListItem(
                    document: doc,
                    isSelected: selectedDocument?.id == doc.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedDocument = doc
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        onDeleteDocument(doc)
                    }
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
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            
            HStack {
                if let latest = document.latestDraft {
                    Text(latest.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No draft")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(document.lastModified, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
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
            // Title bar
            HStack {
                TextField("Thought title", text: $document.title)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .padding()
                
                Spacer()
                
                Button(action: {
                    showingHistory.toggle()
                }) {
                    Label(showingHistory ? "Hide History" : "Show History",
                          systemImage: showingHistory ? "clock.fill" : "clock")
                }
                .buttonStyle(.borderless)
                .padding()
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Editor with optional history
            HSplitView {
                // Main editor
                ModalEditor(document: .constant(document))
                    .frame(minWidth: 500)
                
                // History sidebar (when visible)
                if showingHistory {
                    DraftHistoryView(
                        document: document,
                        onRestore: { draft in
                            document.restoreDraft(draft)
                            onSave()
                        },
                        onClose: {
                            showingHistory = false
                        }
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
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Thought Selected")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Create a new thought or select one from the sidebar")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onNewDocument) {
                Label("New Thought", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DocumentManager())
    }
}
