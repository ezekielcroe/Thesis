// ContentView.swift — Thesis
// Main layout: document sidebar and the editor.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        HSplitView {
            DocumentSidebar(manager: documentManager)
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
    @ObservedObject var manager: DocumentManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Library").font(.headline)
                Spacer()
                Menu {
                    Button("New Document") { manager.createNewDocument() }
                    Button("New Project") { manager.createGroup(.project) }
                    Button("New Shelf") { manager.createGroup(.shelf) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("New document (⌘N), project or shelf")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                ForEach(Library.rows(documents: manager.documents, groups: manager.groups)) { row in
                    switch row {
                    case .group(let group, let depth):
                        groupRow(group, depth: depth)
                    case .document(let document, let depth):
                        documentRow(document, depth: depth)
                    }
                }
            }
            .listStyle(.sidebar)
            // Drop .thesis archives, or text, Markdown and Word files, to open them.
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                Task { @MainActor in Exporter.open(files, into: DocumentManager.shared) }
                return true
            }
        }
    }

    // MARK: - Rows

    private func documentRow(_ doc: Document, depth: Int) -> some View {
        DocumentListItem(document: doc, isSelected: manager.selectedDocument?.id == doc.id)
            .padding(.leading, CGFloat(depth) * 14)
            .contentShape(Rectangle())
            .onTapGesture { manager.selectedDocument = doc }
            // Drag a document onto a shelf or project to move it there.
            .draggable(doc.id.uuidString)
            .contextMenu {
                Button("Rename…") { manager.requestName(for: doc) }
                Menu("Move to") {
                    if Library.groupID(of: doc, in: manager.groups) != nil {
                        Button("Top Level") { manager.move(doc, toGroup: nil) }
                        Divider()
                    }
                    ForEach(Library.destinations(manager.groups), id: \.id) { destination in
                        Button(destination.title) { manager.move(doc, toGroup: destination.id) }
                            .disabled(doc.groupID == destination.id)
                    }
                    if manager.groups.isEmpty {
                        Text("No shelves or projects yet")
                    }
                }
                Button("Move Up") { manager.moveDocument(doc, by: -1) }
                Button("Move Down") { manager.moveDocument(doc, by: 1) }
                Menu("Export") {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.menuTitle) { Exporter.export(doc, as: format) }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) { manager.deleteDocument(doc) }
            }
    }

    private func groupRow(_ group: LibraryGroup, depth: Int) -> some View {
        let count = Library.allDocuments(in: group, documents: manager.documents, groups: manager.groups).count
        return HStack(spacing: 6) {
            Button {
                manager.toggleCollapsed(group.id)
            } label: {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Image(systemName: group.kind.icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(group.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { manager.toggleCollapsed(group.id) }
        .dropDestination(for: String.self) { items, _ in
            let dropped = items.compactMap { UUID(uuidString: $0) }
                .compactMap { id in manager.documents.first(where: { $0.id == id }) }
            guard !dropped.isEmpty else { return false }
            dropped.forEach { manager.move($0, toGroup: group.id) }
            return true
        }
        .contextMenu {
            Button("New Document Here") { manager.createNewDocument(inGroup: group.id) }
            if group.kind == .shelf {
                Button("New Project on This Shelf") { manager.createGroup(.project, onShelf: group.id) }
            }
            Button("Rename…") { manager.renameGroup(group.id) }
            if group.kind == .project {
                Menu("Move to") {
                    Button("Top Level") { manager.moveProject(group.id, toShelf: nil) }
                        .disabled(group.parentID == nil)
                    ForEach(Library.shelves(manager.groups)) { shelf in
                        Button(shelf.name) { manager.moveProject(group.id, toShelf: shelf.id) }
                            .disabled(group.parentID == shelf.id)
                    }
                }
            }
            Button("Move Up") { manager.moveGroup(group.id, by: -1) }
            Button("Move Down") { manager.moveGroup(group.id, by: 1) }
            Menu("Export Documents") {
                ForEach(GroupExportFormat.allCases) { format in
                    Button(format.menuTitle) { Exporter.exportGroup(group, from: manager, as: format) }
                }
            }
            Divider()
            Button("Remove \(group.kind.displayName) (Keep Its Documents)") { manager.removeGroup(group.id) }
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
