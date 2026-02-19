// Document.swift — Thesis
// Core document model: content, branches, version history, annotations

import Foundation
import Combine

class Document: ObservableObject, Identifiable, Codable, Equatable {
    let id: UUID
    @Published var title: String
    @Published var currentContent: String
    @Published var drafts: [Draft]
    @Published var branches: [Branch]
    @Published var activeBranchName: String
    @Published var workingDraft: WorkingDraft?
    @Published var lastModified: Date
    @Published var annotations: [Annotation]
    @Published var sessionChanges: [SemanticChange]
    @Published var yankRegister: String?
    
    // Debounce timer for working draft auto-save
    private var workingDraftTimer: Timer?
    
    enum CodingKeys: String, CodingKey {
        case id, title, currentContent, drafts, branches, activeBranchName
        case workingDraft, lastModified, annotations, sessionChanges
    }
    
    init(title: String = "Untitled Thought") {
        self.id = UUID()
        self.title = title
        self.currentContent = ""
        self.drafts = []
        self.branches = []
        self.activeBranchName = "main"
        self.workingDraft = nil
        self.lastModified = Date()
        self.annotations = []
        self.sessionChanges = []
        self.yankRegister = nil
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        currentContent = try container.decode(String.self, forKey: .currentContent)
        drafts = try container.decode([Draft].self, forKey: .drafts)
        branches = try container.decodeIfPresent([Branch].self, forKey: .branches) ?? []
        activeBranchName = try container.decodeIfPresent(String.self, forKey: .activeBranchName) ?? "main"
        workingDraft = try container.decodeIfPresent(WorkingDraft.self, forKey: .workingDraft)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        annotations = try container.decodeIfPresent([Annotation].self, forKey: .annotations) ?? []
        sessionChanges = try container.decodeIfPresent([SemanticChange].self, forKey: .sessionChanges) ?? []
        yankRegister = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(currentContent, forKey: .currentContent)
        try container.encode(drafts, forKey: .drafts)
        try container.encode(branches, forKey: .branches)
        try container.encode(activeBranchName, forKey: .activeBranchName)
        try container.encode(workingDraft, forKey: .workingDraft)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(sessionChanges, forKey: .sessionChanges)
    }
    
    static func == (lhs: Document, rhs: Document) -> Bool { lhs.id == rhs.id }
    
    // MARK: - Draft Management
    
    func saveFirstDraft(name: String) {
        let autoName = name.isEmpty ? "Draft — \(formattedNow)" : name
        let draft = Draft(
            name: autoName,
            content: currentContent,
            comment: "Initial capture",
            branchName: "main",
            isFirstDraft: true
        )
        drafts.append(draft)
        
        // Create the main branch
        let mainBranch = Branch(name: "main", headDraftId: draft.id, branchPoint: draft.id)
        branches.append(mainBranch)
        activeBranchName = "main"
        
        workingDraft = nil
        sessionChanges = []
        lastModified = Date()
    }
    
    func saveDraft(name: String, comment: String) {
        let parentId = currentBranchHead?.id ?? drafts.last?.id
        let draft = Draft(
            name: name,
            content: currentContent,
            comment: comment,
            parentId: parentId,
            branchName: activeBranchName,
            changes: sessionChanges
        )
        drafts.append(draft)
        
        // Update branch head
        if let idx = branches.firstIndex(where: { $0.name == activeBranchName }) {
            branches[idx].headDraftId = draft.id
        }
        
        workingDraft = nil
        sessionChanges = []
        lastModified = Date()
    }
    
    func restoreDraft(_ draft: Draft) {
        if hasUnsavedChanges {
            let snapshot = Draft(
                name: "Auto-Snapshot",
                content: currentContent,
                comment: "Snapshot before restoring '\(draft.name)'",
                parentId: currentBranchHead?.id,
                branchName: activeBranchName,
                changes: sessionChanges
            )
            drafts.append(snapshot)
            if let idx = branches.firstIndex(where: { $0.name == activeBranchName }) {
                branches[idx].headDraftId = snapshot.id
            }
        }
        currentContent = draft.content
        sessionChanges = []
        scheduleWorkingDraftUpdate()
    }
    
    // MARK: - Branch Management
    
    func createBranch(name: String, description: String = "") {
        guard let headDraft = currentBranchHead else { return }
        
        // Auto-save current changes before branching
        if hasUnsavedChanges {
            saveDraft(name: "Pre-branch snapshot", comment: "Auto-saved before branching to '\(name)'")
        }
        
        let branchPointId = currentBranchHead?.id ?? headDraft.id
        let newBranch = Branch(
            name: name,
            headDraftId: branchPointId,
            branchPoint: branchPointId,
            description: description
        )
        branches.append(newBranch)
        activeBranchName = name
    }
    
    func switchBranch(to name: String) {
        guard let branch = branches.first(where: { $0.name == name }) else { return }
        guard let headDraft = drafts.first(where: { $0.id == branch.headDraftId }) else { return }
        
        // Auto-save if needed
        if hasUnsavedChanges {
            saveDraft(name: "Auto-save", comment: "Auto-saved before switching to '\(name)'")
        }
        
        currentContent = headDraft.content
        activeBranchName = name
        sessionChanges = []
        scheduleWorkingDraftUpdate()
    }
    
    func mergeBranch(sourceName: String) -> MergeResult? {
        guard let sourceBranch = branches.first(where: { $0.name == sourceName }) else { return nil }
        guard let sourceHead = drafts.first(where: { $0.id == sourceBranch.headDraftId }) else { return nil }
        guard let branchPoint = drafts.first(where: { $0.id == sourceBranch.branchPoint }) else { return nil }
        
        let result = DiffGenerator.threeWayMerge(
            ancestor: branchPoint.content,
            ours: currentContent,
            theirs: sourceHead.content
        )
        
        if result.isClean {
            currentContent = result.mergedContent
            
            // Create merge commit
            let mergeCommit = Draft(
                name: "Merge '\(sourceName)' into '\(activeBranchName)'",
                content: result.mergedContent,
                comment: "Merged branch '\(sourceName)'",
                parentId: currentBranchHead?.id,
                secondParentId: sourceHead.id,
                branchName: activeBranchName,
                changes: sessionChanges
            )
            drafts.append(mergeCommit)
            
            if let idx = branches.firstIndex(where: { $0.name == activeBranchName }) {
                branches[idx].headDraftId = mergeCommit.id
            }
            
            sessionChanges = []
        }
        
        return result
    }
    
    func deleteBranch(_ name: String) {
        guard name != "main" && name != activeBranchName else { return }
        branches.removeAll { $0.name == name }
    }
    
    var currentBranchHead: Draft? {
        guard let branch = branches.first(where: { $0.name == activeBranchName }) else {
            return drafts.last
        }
        return drafts.first(where: { $0.id == branch.headDraftId })
    }
    
    var branchNames: [String] { branches.map(\.name) }
    
    var currentBranchDrafts: [Draft] {
        drafts.filter { $0.branchName == activeBranchName }
    }
    
    // MARK: - Change Tracking
    
    func recordChange(_ change: SemanticChange) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionChanges.append(change)
            self?.scheduleWorkingDraftUpdate()
        }
    }
    
    func removeLastChange(matching change: SemanticChange) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let idx = self.sessionChanges.lastIndex(where: { $0.id == change.id }) {
                self.sessionChanges.remove(at: idx)
            }
        }
    }
    
    /// Re-add a change (for redo synchronization)
    func reAddChange(_ change: SemanticChange) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionChanges.append(change)
        }
    }
    
    /// Debounced working draft update — avoids thrashing on rapid edits
    func scheduleWorkingDraftUpdate() {
        workingDraftTimer?.invalidate()
        workingDraftTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.workingDraft = WorkingDraft(
                    content: self.currentContent,
                    pendingChanges: self.sessionChanges
                )
                self.lastModified = Date()
            }
        }
    }
    
    /// Immediate working draft update (for explicit saves)
    func updateWorkingDraftNow() {
        workingDraftTimer?.invalidate()
        workingDraft = WorkingDraft(content: currentContent, pendingChanges: sessionChanges)
        lastModified = Date()
    }
    
    // MARK: - Annotations
    
    func addAnnotation(text: String, anchorText: String, position: Int, category: AnnotationCategory = .note) {
        let annotation = Annotation(text: text, anchorText: anchorText, anchorPosition: position, category: category)
        annotations.append(annotation)
    }
    
    func updateAnnotation(_ annotationId: UUID, text: String? = nil, category: AnnotationCategory? = nil) {
        guard let idx = annotations.firstIndex(where: { $0.id == annotationId }) else { return }
        if let text = text { annotations[idx].text = text }
        if let category = category { annotations[idx].category = category }
        annotations[idx].updatedAt = Date()
    }
    
    func resolveAnnotation(_ annotation: Annotation) {
        if let idx = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[idx].resolved = true
            annotations[idx].updatedAt = Date()
        }
    }
    
    func unresolveAnnotation(_ annotation: Annotation) {
        if let idx = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[idx].resolved = false
            annotations[idx].updatedAt = Date()
        }
    }
    
    func deleteAnnotation(_ annotation: Annotation) {
        annotations.removeAll { $0.id == annotation.id }
    }
    
    /// Refresh all annotation positions against current content
    func refreshAnnotationPositions() {
        for i in annotations.indices {
            annotations[i].updateAnchorPosition(in: currentContent)
        }
    }
    
    var unresolvedAnnotations: [Annotation] {
        annotations.filter { !$0.resolved }
    }
    
    var annotationsByCategory: [AnnotationCategory: [Annotation]] {
        Dictionary(grouping: annotations.filter { !$0.resolved }, by: \.category)
    }
    
    // MARK: - Computed Properties
    
    var hasUnsavedChanges: Bool {
        guard let head = currentBranchHead else { return !currentContent.isEmpty }
        return currentContent != head.content || !sessionChanges.isEmpty
    }
    
    var latestDraft: Draft? { drafts.last }
    
    var allDarlings: [(text: String, draft: String, date: Date)] {
        var result: [(text: String, draft: String, date: Date)] = []
        for draft in drafts {
            for darling in draft.darlings {
                result.append((text: darling, draft: draft.name, date: draft.timestamp))
            }
        }
        for change in sessionChanges {
            if let lost = change.lostText, !lost.isEmpty {
                result.append((text: lost, draft: "Current session", date: change.timestamp))
            }
        }
        return result.reversed()
    }
    
    var sessionChangeSummary: String {
        guard !sessionChanges.isEmpty else { return "No changes" }
        return ChangeSummary(changes: sessionChanges).text
    }
    
    private var formattedNow: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: Date())
    }
}
