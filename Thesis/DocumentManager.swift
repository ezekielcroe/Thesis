// DocumentManager.swift — Thesis
// Document persistence and lifecycle management

import Foundation
import Combine

class DocumentManager: ObservableObject {
    @Published var documents: [Document] = []
    @Published var selectedDocument: Document?
    
    private let saveURL: URL
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let thesisDir = appSupport.appendingPathComponent("Thesis", isDirectory: true)
        try? FileManager.default.createDirectory(at: thesisDir, withIntermediateDirectories: true)
        saveURL = thesisDir.appendingPathComponent("documents.json")
        loadDocuments()
        
        $selectedDocument
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveDocuments() }
            .store(in: &cancellables)
    }
    
    func createNewDocument() {
        let doc = Document(title: "New Thought")
        documents.insert(doc, at: 0)
        selectedDocument = doc
        saveDocuments()
    }
    
    func deleteDocument(_ doc: Document) {
        documents.removeAll { $0.id == doc.id }
        if selectedDocument?.id == doc.id { selectedDocument = documents.first }
        saveDocuments()
    }
    
    func saveDocuments() {
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
            print("Load error: \(error)")
        }
    }
}
