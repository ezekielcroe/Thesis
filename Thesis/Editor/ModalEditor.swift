// ModalEditor.swift — Thesis
// Refactored UI layer: purely declarative, relying on EditorEngine for logic.

import SwiftUI
import AppKit

struct ModalEditor: View {
    @ObservedObject var document: Document
    @Binding var annotationNavPosition: Int?
    
    @StateObject private var engine: EditorEngine
    
    init(document: Document, annotationNavPosition: Binding<Int?> = .constant(nil)) {
        self.document = document
        self._annotationNavPosition = annotationNavPosition
        _engine = StateObject(wrappedValue: EditorEngine(document: document))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                    
                if engine.mode == .comp {
                    CompSplitView(
                        diffChanges: engine.diffChanges,
                        currentIndex: engine.currentDiffIndex,
                        onKeyPress: { key, mods in engine.handleKeyPress(key, modifiers: mods) }
                    )
                    .border(engine.mode.borderColor, width: 3)
                    .transition(.opacity)
                } else {
                    EditorTextView(
                        text: $document.currentContent,
                        mode: $engine.mode,
                        cursorPosition: $engine.cursorPosition,
                        highlightRange: $engine.highlightRange,
                        flashRange: $engine.flashRange,
                        selectionRange: $engine.selectionRange,
                        diffChanges: $engine.diffChanges,
                        onTextChange: { engine.handleTextChange() },
                        onKeyPress: { key, mods in engine.handleKeyPress(key, modifiers: mods) },
                        onModeChange: { newMode in engine.handleModeChange(newMode) }
                    )
                    .border(engine.mode.borderColor, width: 3)
                }
                    
                // Overlays
                if let verb = engine.pendingVerb {
                    VerbHelpOverlay(verb: verb.verb)
                        .padding(8)
                        .transition(.opacity)
                }
                
                if engine.pendingArgument {
                    ArgumentHelpOverlay()
                        .padding(8)
                        .transition(.opacity)
                }
                    
                if engine.movePayload != nil {
                        MoveIndicator()
                            .padding(8)
                            .transition(.opacity)
                }
            }
            
            // The Status Bar
            StatusBar(
                mode: engine.mode,
                pendingVerb: engine.pendingVerb?.verb,
                stats: engine.stats,
                draftInfo: draftInfo,
                hasUnsavedChanges: document.hasUnsavedChanges,
                branchInfo: branchInfo,
                diffInfo: currentDiffInfo,
                undoPreview: engine.undoStack.undoPreview,
                annotationCount: document.unresolvedAnnotations.count,
                sessionSummary: document.sessionChangeSummary,
                searchMatchCount: engine.searchMatches.count,
                pendingArgument: engine.pendingArgument
            )
        }
        .sheet(item: $engine.activeSheet) { sheetType in
            switch sheetType {
            case .firstDraft:
                FirstDraftSheet(
                    onSave: { name in
                        document.saveFirstDraft(name: name)
                        engine.mode = .normal
                    },
                    onCancel: { engine.mode = .freeText }
                )
            case .save:
                SaveDraftSheet(
                    sessionSummary: document.sessionChangeSummary,
                    onSave: { name, comment in
                        document.saveDraft(name: name, comment: comment)
                        engine.mode = .normal
                        engine.handleTextChange()
                    }
                )
            case .annotation(let anchorText, let position):
                AnnotationSheet(
                    anchorText: anchorText,
                    onSave: { noteText in
                        document.addAnnotation(text: noteText, anchorText: anchorText, position: position)
                        engine.mode = .normal
                    }
                )
            case .citation(let anchorText, let insertPosition):
                CitationSheet(
                    anchorText: anchorText,
                    existingKeys: Set(document.citations.map(\.key)),
                    onSave: { key, source in
                        let marker = " [\(key)]"
                        let nsText = document.currentContent as NSString
                        let safePos = min(insertPosition, nsText.length)
                        document.currentContent = nsText.replacingCharacters(
                            in: NSRange(location: safePos, length: 0),
                            with: marker
                        )
                        document.addCitation(key: key, source: source, anchorText: anchorText)
                        engine.cursorPosition = safePos + marker.count
                        engine.handleTextChange()
                        engine.mode = .normal
                    }
                )
            case .branch:
                BranchSheet(
                    document: document,
                    onCreateBranch: { name, desc in
                        document.createBranch(name: name, description: desc)
                        engine.mode = .normal
                    },
                    onSwitchBranch: { name in
                        document.switchBranch(to: name)
                        engine.mode = .normal
                        engine.analyzer.invalidate()
                        engine.handleTextChange()
                    },
                    onDeleteBranch: { name in document.deleteBranch(name) }
                )
            case .merge:
                MergeSheet(
                    document: document,
                    onMerge: { sourceBranch in
                        _ = document.mergeBranch(sourceName: sourceBranch)
                        engine.mode = .normal
                        engine.analyzer.invalidate()
                        engine.handleTextChange()
                    }
                )
            case .log:
                LogSheet(
                    document: document,
                    onRestore: { draft in
                        document.restoreDraft(draft)
                        engine.analyzer.invalidate()
                        engine.handleTextChange()
                    }
                )
            case .help:
                HelpSheet()
            }
        }
        .onChange(of: annotationNavPosition) {
            if let position = annotationNavPosition {
                engine.navigateToPosition(position)
                annotationNavPosition = nil
            }
        }
    }
    
    // MARK: - Computed Status Variables
    
    private var draftInfo: String {
        if let head = document.currentBranchHead {
            return "\(document.activeBranchName): \(head.name)"
        }
        return "No draft saved"
    }
    
    private var branchInfo: String? {
        document.branches.count > 1 ? "[\(document.activeBranchName)]" : nil
    }
    
    private var currentDiffInfo: EditorDiffInfo? {
        guard engine.mode == .comp, !engine.diffChanges.isEmpty else { return nil }
        let changeIndices = DiffGenerator.getChangeIndices(in: engine.diffChanges)
        guard !changeIndices.isEmpty else { return nil }
        
        let positionInChanges = changeIndices.firstIndex(of: engine.currentDiffIndex) ?? 0
        
        let currentChange = engine.diffChanges.indices.contains(engine.currentDiffIndex)
            ? engine.diffChanges[engine.currentDiffIndex]
            : engine.diffChanges[changeIndices[positionInChanges]]
        
        return EditorDiffInfo(
            currentIndex: positionInChanges,
            totalChanges: changeIndices.count,
            currentChange: currentChange
        )
    }
}

// MARK: - Move Indicator

struct MoveIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.arrow.down")
            Text("MOVING — j/k to position, Enter to confirm, ESC to cancel")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.purple)
        .cornerRadius(6)
    }
}

// MARK: - Argument Help Overlay

struct ArgumentHelpOverlay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ARGUMENT STRUCTURE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Divider()
            ForEach(ArgumentType.helpItems, id: \.key) { item in
                HStack(spacing: 8) {
                    Text(item.key)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(width: 16, alignment: .center)
                        .foregroundColor(.teal)
                    Text(item.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Divider()
            Text("ESC to cancel")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
