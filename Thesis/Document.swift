import Foundation
import Combine

class Document: ObservableObject, Identifiable, Codable, Equatable {
    let id: UUID
    @Published var title: String
    @Published var currentContent: String
    @Published var drafts: [Draft]
    @Published var workingDraft: WorkingDraft?
    @Published var lastModified: Date
    
    // BUGFIX #3: Track the active branch parent for correct genealogy
    // When user restores a draft and saves, the new draft should parent to the restored draft
    @Published var activeBranchParentId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case id, title, currentContent, drafts, workingDraft, lastModified, activeBranchParentId
    }
    
    init(title: String = "Untitled Thought") {
        self.id = UUID()
        self.title = title
        self.currentContent = ""
        self.drafts = []
        self.workingDraft = nil
        self.lastModified = Date()
        self.activeBranchParentId = nil
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        currentContent = try container.decode(String.self, forKey: .currentContent)
        drafts = try container.decode([Draft].self, forKey: .drafts)
        workingDraft = try container.decodeIfPresent(WorkingDraft.self, forKey: .workingDraft)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        activeBranchParentId = try container.decodeIfPresent(UUID.self, forKey: .activeBranchParentId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(currentContent, forKey: .currentContent)
        try container.encode(drafts, forKey: .drafts)
        try container.encode(workingDraft, forKey: .workingDraft)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(activeBranchParentId, forKey: .activeBranchParentId)
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
        // Set the active branch to this new draft
        activeBranchParentId = draft.id
    }
    
    func saveDraft(name: String, comment: String) {
        // BUGFIX #3: Use activeBranchParentId for correct genealogy
        // This ensures that if user restored Draft #2 and saves, the new draft
        // correctly parents to Draft #2, not just drafts.last
        let parentId = activeBranchParentId ?? drafts.last?.id
        
        let draft = Draft(
            name: name,
            content: currentContent,
            comment: comment,
            parentId: parentId
        )
        drafts.append(draft)
        workingDraft = nil
        lastModified = Date()
        
        // Update active branch to point to the new draft
        activeBranchParentId = draft.id
    }
    
    // BUGFIX #3: Non-destructive draft restoration with auto-snapshot
    func restoreDraft(_ draft: Draft) {
        // Safety Check: Is the current state dirty (has unsaved changes)?
        if hasUnsavedChanges {
            // Create an automatic snapshot before overwriting
            let snapshot = Draft(
                name: "Auto-Snapshot",
                content: currentContent,
                comment: "Snapshot taken before restoring '\(draft.name)'",
                parentId: latestDraft?.id
            )
            drafts.append(snapshot)
        }
        
        // Restore the content
        currentContent = draft.content
        
        // BUGFIX #3: Update the branch pointer to the restored draft
        // Next save will correctly parent to this draft, not the chronological last
        activeBranchParentId = draft.id
        
        // Update working draft
        updateWorkingDraft()
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
    
    var hasUnsavedChanges: Bool {
        guard let lastDraft = drafts.last else {
            return !currentContent.isEmpty
        }
        return currentContent != lastDraft.content
    }
    
    var latestDraft: Draft? {
        return drafts.last
    }
    
    // MARK: - Branch Information (for UI display)
    
    /// Returns the draft that the current working content is branching from
    var currentBranchParent: Draft? {
        guard let parentId = activeBranchParentId else { return nil }
        return drafts.first { $0.id == parentId }
    }
    
    /// Returns true if the current content is branching from a non-latest draft
    var isBranching: Bool {
        guard let parentId = activeBranchParentId,
              let latestId = latestDraft?.id else {
            return false
        }
        return parentId != latestId
    }
}
