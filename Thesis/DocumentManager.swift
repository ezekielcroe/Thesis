import Foundation
import Combine

class DocumentManager: ObservableObject {
    @Published var documents: [Document] = []
    @Published var selectedDocument: Document?
    
    private let saveKey = "ThesisDocumentsMVP"
    private var cancellables = Set<AnyCancellable>()
    private var autoSaveTimer: Timer?
    
    init() {
        loadDocuments()
        setupAutoSave()
    }
    
    private func setupAutoSave() {
        // Auto-save every 30 seconds
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.saveDocuments()
        }
    }
    
    func createNewDocument() {
        let doc = Document()
        documents.append(doc)
        selectedDocument = doc
        saveDocuments()
    }
    
    func deleteDocument(_ document: Document) {
        documents.removeAll { $0.id == document.id }
        if selectedDocument?.id == document.id {
            selectedDocument = documents.first
        }
        saveDocuments()
    }
    
    func saveDocuments() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(documents)
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            print("Failed to save documents: \(error)")
        }
    }
    
    private func loadDocuments() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else {
            createWelcomeDocument()
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            documents = try decoder.decode([Document].self, from: data)
            selectedDocument = documents.first
        } catch {
            print("Failed to load documents: \(error)")
            createWelcomeDocument()
        }
    }
    
    private func createWelcomeDocument() {
        let welcome = Document(title: "Welcome to Thesis")
        welcome.currentContent = """
Welcome to Thesis - A modal editor for thought evolution.

You are currently in INSERT mode. Type freely to capture your thoughts.

When ready, press ESC. You'll be prompted to save this as your First Draft.

After saving, you'll enter EDIT mode where you can:
- Navigate: h (prev sentence), l (next sentence), j (next para), k (prev para)
- Delete: dw (word), das (sentence), dap (paragraph), D (to end of sentence)
- Change: cw (word), cas (sentence), cap (paragraph), C (to end of sentence)
- Insert: i (insert word), a (append sentence)
- Undo: u (undo last 10 commands)

To review your changes:
- Type :comp or press Cmd+D to see a diff view
- Use n (next change) and p (previous change) to navigate
- Type :print or press Cmd+S to save as a new draft

Try editing this document to learn the workflow!
"""
        documents.append(welcome)
        selectedDocument = welcome
        saveDocuments()
    }
    
    deinit {
        autoSaveTimer?.invalidate()
    }
}
