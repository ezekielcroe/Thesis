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

    func createNewDocument() {
        let doc = Document(title: "Untitled")
        documents.insert(doc, at: 0)
        selectedDocument = doc
        saveDocuments()
        requestName(for: doc, isNew: true)
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
    func importDocuments(_ imported: [Document], resolve: @MainActor (Document) -> ImportChoice) {
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
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(documents)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Save error: \(error)")
        }
    }

    private func loadDocuments() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            documents = try decoder.decode([Document].self, from: data)
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
