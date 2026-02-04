import Foundation
import Combine

class Document: ObservableObject, Identifiable, Codable, Equatable {
    let id: UUID
    @Published var title: String
    @Published var currentContent: String
    @Published var drafts: [Draft]
    @Published var workingDraft: WorkingDraft?
    @Published var lastModified: Date
    
    enum CodingKeys: String, CodingKey {
        case id, title, currentContent, drafts, workingDraft, lastModified
    }
    
    init(title: String = "Untitled Thought") {
        self.id = UUID()
        self.title = title
        self.currentContent = ""
        self.drafts = []
        self.workingDraft = nil
        self.lastModified = Date()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        currentContent = try container.decode(String.self, forKey: .currentContent)
        drafts = try container.decode([Draft].self, forKey: .drafts)
        workingDraft = try container.decodeIfPresent(WorkingDraft.self, forKey: .workingDraft)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(currentContent, forKey: .currentContent)
        try container.encode(drafts, forKey: .drafts)
        try container.encode(workingDraft, forKey: .workingDraft)
        try container.encode(lastModified, forKey: .lastModified)
    }
    
    // MARK: - Equatable Conformance
    static func == (lhs: Document, rhs: Document) -> Bool {
        lhs.id == rhs.id
    }
    
    func saveFirstDraft(name: String) {
        let draft = Draft(
            name: name,
            content: currentContent,
            comment: "Initial capture",
            isFirstDraft: true
        )
        drafts.append(draft)
        workingDraft = nil
        lastModified = Date()
    }
    
    func saveDraft(name: String, comment: String) {
        let draft = Draft(
            name: name,
            content: currentContent,
            comment: comment,
            parentId: drafts.last?.id
        )
        drafts.append(draft)
        workingDraft = nil
        lastModified = Date()
    }
    
    // FIX: Use async update to avoid "Publishing changes from within view updates" warning
    func updateWorkingDraft() {
        // Schedule the update for the next run loop to avoid SwiftUI state conflicts
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.workingDraft = WorkingDraft(content: self.currentContent)
            self.lastModified = Date()
        }
    }
    
    func restoreDraft(_ draft: Draft) {
        currentContent = draft.content
        // FIX: Call updateWorkingDraft which now handles async properly
        updateWorkingDraft()
    }
    
    var hasUnsavedChanges: Bool {
        guard let lastDraft = drafts.last else {
            return !currentContent.isEmpty
        }
        return currentContent != lastDraft.content
    }
    
    var latestDraft: Draft? {
        return drafts.last
    }
}
