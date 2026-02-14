import Foundation
import Combine

class Document: ObservableObject, Identifiable, Codable, Equatable {
    let id: UUID
    @Published var title: String
    @Published var currentContent: String
    @Published var drafts: [Draft]
    @Published var workingDraft: WorkingDraft?
    @Published var lastModified: Date
    
    // Branch tracking for version control
    @Published var activeBranchParentId: UUID?
    @Published var sessionChanges: [SemanticChange]
    
    enum CodingKeys: String, CodingKey {
        case id, title, currentContent, drafts, workingDraft, lastModified
        case activeBranchParentId, sessionChanges
    }
    
    init(title: String = "Untitled Thought") {
        self.id = UUID()
        self.title = title
        self.currentContent = ""
        self.drafts = []
        self.workingDraft = nil
        self.lastModified = Date()
        self.activeBranchParentId = nil
        self.sessionChanges = []
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
        
        // Safely decode sessionChanges, defaulting to empty if missing from older saves
        sessionChanges = try container.decodeIfPresent([SemanticChange].self, forKey: .sessionChanges) ?? []
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
        try container.encode(sessionChanges, forKey: .sessionChanges)
    }
    
    static func == (lhs: Document, rhs: Document) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Draft Management with Semantic Changes
    
    func saveFirstDraft(name: String) {
        let draft = Draft(
            name: name,
            content: currentContent,
            comment: "Initial capture",
            isFirstDraft: true,
            changes: []  // No changes for first draft
        )
        drafts.append(draft)
        workingDraft = nil
        sessionChanges = []  // Clear session changes
        lastModified = Date()
        activeBranchParentId = draft.id
    }
    
    func saveDraft(name: String, comment: String) {
        let parentId = activeBranchParentId ?? drafts.last?.id
        
        // Use accumulated session changes
        let draft = Draft(
            name: name,
            content: currentContent,
            comment: comment,
            parentId: parentId,
            changes: sessionChanges
        )
        
        drafts.append(draft)
        workingDraft = nil
        sessionChanges = []  // Clear for next session
        lastModified = Date()
        activeBranchParentId = draft.id
    }
    
    func restoreDraft(_ draft: Draft) {
        // Safety Check: Is the current state dirty?
        if hasUnsavedChanges {
            let snapshot = Draft(
                name: "Auto-Snapshot",
                content: currentContent,
                comment: "Snapshot taken before restoring '\(draft.name)'",
                parentId: latestDraft?.id,
                changes: sessionChanges
            )
            drafts.append(snapshot)
        }
        
        currentContent = draft.content
        activeBranchParentId = draft.id
        sessionChanges = []  // Clear changes when restoring
        updateWorkingDraft()
    }
    
    // NEW: Add a semantic change to the session
    // This fixes the error: "Value of type 'Document' has no dynamic member 'recordChange'"
    func recordChange(_ change: SemanticChange) {
        // We use MainActor logic (via dispatch) to ensure UI updates are safe
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sessionChanges.append(change)
            self.updateWorkingDraft()
        }
    }
    
    func updateWorkingDraft() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.workingDraft = WorkingDraft(
                content: self.currentContent,
                pendingChanges: self.sessionChanges
            )
            self.lastModified = Date()
        }
    }
    
    var hasUnsavedChanges: Bool {
        guard let lastDraft = drafts.last else {
            return !currentContent.isEmpty
        }
        // It's unsaved if text changed OR if we have tracked semantic changes
        return currentContent != lastDraft.content || !sessionChanges.isEmpty
    }
    
    var latestDraft: Draft? {
        return drafts.last
    }
    
    // MARK: - Branch Information
    
    var currentBranchParent: Draft? {
        guard let parentId = activeBranchParentId else { return nil }
        return drafts.first { $0.id == parentId }
    }
    
    var isBranching: Bool {
        guard let parentId = activeBranchParentId,
              let latestId = latestDraft?.id else {
            return false
        }
        return parentId != latestId
    }
    
    // MARK: - Session Change Summary
    
    var sessionChangeSummary: String {
        guard !sessionChanges.isEmpty else {
            return "No changes in session"
        }
        return ChangeSummary(changes: sessionChanges).text
    }
}
