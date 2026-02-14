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

    --- MODE SWITCHING ---
    ESC        : Exit Insert/Command modes -> Edit Mode
    i          : Insert (Word context)
    a          : Append (Jump to end of sentence -> Insert)
    :          : Enter Command Mode (type 'comp' or 'print')

    --- NAVIGATION ---
    Clauses    : h (prev), l (next)
    Sentences  : Shift+H (prev), Shift+L (next)
    Paragraphs : k (prev), j (next)
    Lines      : Shift+K (prev), Shift+J (next)
    Words      : b (prev), w (next)

    --- SEMANTIC EDITING ---
    (d=delete, c=change/replace, r=refine)

    Clauses:
      dc  : Delete Clause
      cc  : Change Clause
      rc  : Refine Clause

    Sentences:
      das : Delete Sentence
      cas : Change Sentence
      rs  : Refine Sentence

    Paragraphs:
      dap : Delete Paragraph
      cap : Change Paragraph
      rp  : Refine Paragraph

    Words:
      dw  : Delete Word (Forward)
      db  : Delete Word (Backward)
      cw  : Change Word
      rw  : Refine Word

    To End of Sentence:
      D   : Delete to end
      C   : Change to end
      R   : Refine to end

    --- HISTORY & REVIEW ---
    u          : Undo last command
    Cmd+D      : Compare Mode (Diff View)
    Cmd+S      : Save/Print Draft

    In Compare Mode:
      n / p    : Next / Previous change
      ESC      : Exit comparison
    """
            documents.append(welcome)
            selectedDocument = welcome
            saveDocuments()
        }
    
    deinit {
        autoSaveTimer?.invalidate()
    }
}
