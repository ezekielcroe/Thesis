// DocumentManager.swift — Thesis
// Document persistence and lifecycle management

import Foundation
import Combine
import AppKit

/// What to do when an imported document is already in the library.
enum ImportChoice { case keepBoth, replace, skip }

final class DocumentManager: ObservableObject {
    @Published var documents: [Document] = [] {
        didSet { observeDocuments() }
    }
    @Published var selectedDocument: Document?
    /// Shelves and projects (see Library.swift). Documents point at theirs with `groupID`.
    @Published var groups: [LibraryGroup] = [] {
        didSet { saveRequests.send() }
    }

    /// Non-nil when the save file existed but couldn't be read. Shown to the user.
    @Published var loadErrorMessage: String?

    /// False only if the save file was unreadable AND we failed to back it up.
    /// In that state, saving would replace the user's only copy with whatever is
    /// in memory (usually nothing), so we refuse.
    private var savingAllowed = true

    private let saveURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var documentObservers = Set<AnyCancellable>()
    private let saveRequests = PassthroughSubject<Void, Never>()

    /// One library per app. Shared so the app delegate can hand it files opened from Finder,
    /// which can arrive before any window exists.
    static let shared = DocumentManager()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let thesisDir = appSupport.appendingPathComponent("Thesis", isDirectory: true)
        try? FileManager.default.createDirectory(at: thesisDir, withIntermediateDirectories: true)
        saveURL = thesisDir.appendingPathComponent("documents.json")
        loadDocuments()

        // Any change to any document (content, title, drafts, notes…) schedules a save.
        // Previously only *selection* changes triggered autosave, because Document is a
        // class and mutating it never republishes `selectedDocument`.
        saveRequests
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in self?.saveDocuments() }
            .store(in: &cancellables)

        $selectedDocument
            .dropFirst()
            .sink { [weak self] _ in self?.saveRequests.send() }
            .store(in: &cancellables)

        // On quit: take the automatic snapshot the setting asks for (so cuts reach
        // Darlings), then flush, so the last second of typing isn't lost to the debounce.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if SnapshotSettings.current.trigger != .manual {
                    self.documents.forEach { _ = $0.takeSnapshot() }
                }
                self.saveDocuments()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.saveDocuments() }
            .store(in: &cancellables)
    }

    private func observeDocuments() {
        documentObservers.removeAll()
        for doc in documents {
            doc.objectWillChange
                .sink { [weak self] _ in self?.saveRequests.send() }
                .store(in: &documentObservers)
        }
    }

    /// A new document next to the selected one: in the same shelf or project, if any.
    func createNewDocument() {
        let group = selectedDocument.flatMap { Library.groupID(of: $0, in: groups) }
        createNewDocument(inGroup: group)
    }

    func createNewDocument(inGroup groupID: UUID?) {
        let doc = Document(title: "Untitled")
        doc.groupID = groupID
        if let groupID = groupID {
            documents.append(doc)                       // last in its group
            setCollapsed(false, revealing: groupID)
        } else {
            documents.insert(doc, at: 0)
        }
        selectedDocument = doc
        saveDocuments()
        requestName(for: doc, isNew: true)
    }

    // MARK: - Shelves and projects

    func createGroup(_ kind: LibraryGroup.Kind, onShelf shelfID: UUID? = nil) {
        Task { @MainActor in
            guard let name = NamePrompt.ask(
                title: "New \(kind.displayName.lowercased())",
                message: kind == .shelf
                    ? "A shelf holds projects and documents."
                    : "A project holds the documents of one piece of work: a thesis, a book, a screenplay.",
                initialValue: "",
                confirmTitle: "Create"
            ) else { return }
            self.groups.append(LibraryGroup(name: name, kind: kind, parentID: shelfID))
            if let shelfID = shelfID { self.setCollapsed(false, revealing: shelfID) }
        }
    }

    func renameGroup(_ id: UUID) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        Task { @MainActor in
            guard let name = NamePrompt.ask(
                title: "Rename \(group.kind.displayName.lowercased())",
                message: "Enter a new name.",
                initialValue: group.name,
                confirmTitle: "Rename"
            ), let index = self.groups.firstIndex(where: { $0.id == id }) else { return }
            self.groups[index].name = name
        }
    }

    /// Removes the shelf or project but keeps what was in it, moved up one level.
    func removeGroup(_ id: UUID) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        let destination = group.kind == .project ? group.parentID : nil
        for doc in documents where doc.groupID == id { doc.groupID = destination }
        var remaining = groups.filter { $0.id != id }
        for index in remaining.indices where remaining[index].parentID == id {
            remaining[index].parentID = nil
        }
        groups = remaining
    }

    func toggleCollapsed(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isCollapsed.toggle()
    }

    /// Opens a group (and the shelf it is on) so something just put in it can be seen.
    private func setCollapsed(_ collapsed: Bool, revealing id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        if groups[index].isCollapsed != collapsed { groups[index].isCollapsed = collapsed }
        if let parent = groups[index].parentID, let parentIndex = groups.firstIndex(where: { $0.id == parent }),
           groups[parentIndex].isCollapsed != collapsed {
            groups[parentIndex].isCollapsed = collapsed
        }
    }

    /// Moves a document into a shelf or project (nil: out to the top level), as its last item.
    func move(_ doc: Document, toGroup groupID: UUID?) {
        guard let index = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        doc.groupID = groupID
        var reordered = documents
        reordered.remove(at: index)
        reordered.append(doc)
        documents = reordered
        if let groupID = groupID { setCollapsed(false, revealing: groupID) }
    }

    /// Puts a project on a shelf (nil: at the top level).
    func moveProject(_ id: UUID, toShelf shelfID: UUID?) {
        guard let index = groups.firstIndex(where: { $0.id == id }), groups[index].kind == .project else { return }
        var project = groups[index]
        project.parentID = shelfID
        var reordered = groups
        reordered.remove(at: index)
        reordered.append(project)
        groups = reordered
        if let shelfID = shelfID { setCollapsed(false, revealing: shelfID) }
    }

    /// Moves a document one place up (-1) or down (+1) among the documents in its group.
    func moveDocument(_ doc: Document, by offset: Int) {
        let siblings = Library.documents(in: Library.groupID(of: doc, in: groups), documents: documents, groups: groups)
        guard let position = siblings.firstIndex(where: { $0.id == doc.id }),
              siblings.indices.contains(position + offset),
              let a = documents.firstIndex(where: { $0.id == doc.id }),
              let b = documents.firstIndex(where: { $0.id == siblings[position + offset].id }) else { return }
        documents.swapAt(a, b)
    }

    /// Moves a shelf or project one place up or down among its siblings.
    func moveGroup(_ id: UUID, by offset: Int) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        let siblings: [LibraryGroup]
        if group.kind == .shelf {
            siblings = Library.shelves(groups)
        } else {
            let shelfIDs = Set(Library.shelves(groups).map(\.id))
            let shelf = group.parentID.flatMap { shelfIDs.contains($0) ? $0 : nil }
            siblings = Library.projects(onShelf: shelf, groups: groups)
        }
        guard let position = siblings.firstIndex(where: { $0.id == id }),
              siblings.indices.contains(position + offset),
              let a = groups.firstIndex(where: { $0.id == id }),
              let b = groups.firstIndex(where: { $0.id == siblings[position + offset].id }) else { return }
        groups.swapAt(a, b)
    }

    // MARK: - Naming

    /// Asks for a title in a standard dialog. Runs on the next turn of the main loop, so
    /// it never interrupts a key event or a view update. Cancel, or an empty name,
    /// keeps the current title.
    func requestName(for doc: Document, isNew: Bool = false) {
        Task { @MainActor in
            guard let name = NamePrompt.ask(
                title: isNew ? "Name your document" : "Rename document",
                message: isNew ? "You can rename it later by clicking its title." : "Enter a new title.",
                initialValue: isNew ? "" : doc.title,
                confirmTitle: isNew ? "Create" : "Rename"
            ) else { return }
            doc.title = name
        }
    }

    // MARK: - Import

    /// Adds documents read from an archive. If one is already here (same identity),
    /// `resolve` decides: keep both (the import gets its own identity), replace, or skip.
    @MainActor
    func importDocuments(_ imported: [Document], groups importedGroups: [LibraryGroup] = [],
                         resolve: @MainActor (Document) -> ImportChoice) {
        // Shelves and projects from a library backup, unless they're already here.
        let newGroups = importedGroups.filter { group in !groups.contains(where: { $0.id == group.id }) }
        if !newGroups.isEmpty { groups += newGroups }
        var lastAdded: Document?
        for doc in imported {
            if let index = documents.firstIndex(where: { $0.id == doc.id }) {
                switch resolve(doc) {
                case .keepBoth:
                    doc.assignNewIdentity()
                    doc.title += " (archived)"
                    documents.insert(doc, at: 0)
                case .replace:
                    if selectedDocument?.id == doc.id { selectedDocument = nil }
                    documents[index] = doc
                case .skip:
                    continue
                }
            } else {
                documents.insert(doc, at: 0)
            }
            lastAdded = doc
        }
        if let doc = lastAdded { selectedDocument = doc }
        saveDocuments()
    }

    func deleteDocument(_ doc: Document) {
        documents.removeAll { $0.id == doc.id }
        if selectedDocument?.id == doc.id { selectedDocument = documents.first }
        saveDocuments()
    }

    func saveDocuments() {
        guard savingAllowed else {
            print("Save skipped: the existing save file could not be read or backed up.")
            return
        }
        do {
            // Same format as a .thesis backup of the whole library: documents plus groups.
            let data = try DocumentExport.archiveData(documents, groups: groups)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Save error: \(error)")
        }
    }

    private func loadDocuments() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            // Reads the current format, and the plain list of documents earlier versions saved.
            let library = try DocumentExport.library(fromArchive: data)
            documents = library.documents
            groups = library.groups
            selectedDocument = documents.first
        } catch {
            // Never let a failed load turn into an overwrite. Keep a copy of the file
            // the user can recover from, and only allow saving once that copy exists.
            let backupURL = preserveUnreadableFile()
            savingAllowed = (backupURL != nil)
            if let backupURL {
                loadErrorMessage = "Your documents couldn't be opened (\(error.localizedDescription)). "
                    + "The original file was kept safe at:\n\(backupURL.path)"
            } else {
                loadErrorMessage = "Your documents couldn't be opened (\(error.localizedDescription)), "
                    + "and a backup couldn't be made. Saving is disabled so the file at "
                    + "\(saveURL.path) is not overwritten."
            }
            print("Load error: \(error)")
        }
    }

    private func preserveUnreadableFile() -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = saveURL.deletingLastPathComponent()
            .appendingPathComponent("documents-unreadable-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: saveURL, to: backupURL)
            return backupURL
        } catch {
            print("Backup error: \(error)")
            return nil
        }
    }
}
