// UndoSystem.swift — Thesis
// Operation-based undo/redo that stays in sync with semantic change history

import Foundation
import Combine

// MARK: - Undoable Operation Protocol

protocol UndoableOperation {
    var description: String { get }
    func undo(content: inout String) -> Int
    func redo(content: inout String) -> Int
    var semanticChange: SemanticChange? { get }
}

// MARK: - Delete Operation

struct DeleteOperation: UndoableOperation {
    let range: NSRange
    let deletedText: String
    let cursorBefore: Int
    let semanticChange: SemanticChange?
    
    var description: String { "Delete \"\(String(deletedText.prefix(30)))\"" }
    
    func undo(content: inout String) -> Int {
        let nsContent = content as NSString
        let location = min(range.location, nsContent.length)
        content = nsContent.replacingCharacters(
            in: NSRange(location: location, length: 0),
            with: deletedText
        )
        return cursorBefore
    }
    
    func redo(content: inout String) -> Int {
        let nsContent = content as NSString
        let safeRange = TextAnalyzer.safeRange(range, in: nsContent.length)
        content = nsContent.replacingCharacters(in: safeRange, with: "")
        return safeRange.location
    }
}

// MARK: - Insert Operation

struct InsertOperation: UndoableOperation {
    let position: Int
    let insertedText: String
    let semanticChange: SemanticChange?
    
    var description: String { "Insert \"\(String(insertedText.prefix(30)))\"" }
    
    func undo(content: inout String) -> Int {
        let nsContent = content as NSString
        let removeRange = NSRange(
            location: min(position, nsContent.length),
            length: min(insertedText.count, nsContent.length - min(position, nsContent.length))
        )
        content = nsContent.replacingCharacters(in: removeRange, with: "")
        return position
    }
    
    func redo(content: inout String) -> Int {
        let nsContent = content as NSString
        let location = min(position, nsContent.length)
        content = nsContent.replacingCharacters(
            in: NSRange(location: location, length: 0),
            with: insertedText
        )
        return location + insertedText.count
    }
}

// MARK: - Replace Operation

struct ReplaceOperation: UndoableOperation {
    let range: NSRange
    let oldText: String
    let newText: String
    let cursorBefore: Int
    let semanticChange: SemanticChange?
    
    var description: String { "Replace \"\(String(oldText.prefix(20)))\" → \"\(String(newText.prefix(20)))\"" }
    
    func undo(content: inout String) -> Int {
        let nsContent = content as NSString
        let location = min(range.location, nsContent.length)
        let replaceRange = NSRange(
            location: location,
            length: min(newText.count, nsContent.length - location)
        )
        content = nsContent.replacingCharacters(in: replaceRange, with: oldText)
        return cursorBefore
    }
    
    func redo(content: inout String) -> Int {
        let nsContent = content as NSString
        let location = min(range.location, nsContent.length)
        let replaceRange = NSRange(
            location: location,
            length: min(oldText.count, nsContent.length - location)
        )
        content = nsContent.replacingCharacters(in: replaceRange, with: newText)
        return location + newText.count
    }
}

// MARK: - Move Operation

struct MoveOperation: UndoableOperation {
    let sourceRange: NSRange
    let movedText: String
    let destinationPosition: Int
    let cursorBefore: Int
    let semanticChange: SemanticChange?
    
    var description: String { "Move \"\(String(movedText.prefix(30)))\"" }
    
    func undo(content: inout String) -> Int {
        // Remove from destination
        let nsContent1 = content as NSString
        let destRange: NSRange
        if destinationPosition <= sourceRange.location {
            destRange = NSRange(location: destinationPosition, length: movedText.count)
        } else {
            destRange = NSRange(location: destinationPosition - sourceRange.length, length: movedText.count)
        }
        let safeDestRange = TextAnalyzer.safeRange(destRange, in: nsContent1.length)
        content = nsContent1.replacingCharacters(in: safeDestRange, with: "")
        
        // Reinsert at source
        let nsContent2 = content as NSString
        let sourcePos = min(sourceRange.location, nsContent2.length)
        content = nsContent2.replacingCharacters(
            in: NSRange(location: sourcePos, length: 0),
            with: movedText
        )
        return cursorBefore
    }
    
    func redo(content: inout String) -> Int {
        // Remove from source
        let nsContent1 = content as NSString
        let safeSource = TextAnalyzer.safeRange(sourceRange, in: nsContent1.length)
        content = nsContent1.replacingCharacters(in: safeSource, with: "")
        
        // Insert at destination (adjusted)
        let nsContent2 = content as NSString
        let adjustedDest: Int
        if destinationPosition > sourceRange.location {
            adjustedDest = destinationPosition - sourceRange.length
        } else {
            adjustedDest = destinationPosition
        }
        let safeDest = min(adjustedDest, nsContent2.length)
        content = nsContent2.replacingCharacters(
            in: NSRange(location: safeDest, length: 0),
            with: movedText
        )
        return safeDest + movedText.count
    }
}

// MARK: - Undo Stack

class UndoStack: ObservableObject {
    var objectWillChange = ObservableObjectPublisher()
    
    private var undoHistory: [UndoableOperation] = []
    private var redoHistory: [UndoableOperation] = []
    private let maxSize = 200
    
    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }
    var count: Int { undoHistory.count }
    
    var undoPreview: String? { undoHistory.last?.description }
    var redoPreview: String? { redoHistory.last?.description }
    
    func push(_ operation: UndoableOperation) {
        undoHistory.append(operation)
        redoHistory.removeAll()
        if undoHistory.count > maxSize { undoHistory.removeFirst() }
    }
    
    func undo(content: inout String) -> (cursor: Int, change: SemanticChange?)? {
        guard let operation = undoHistory.popLast() else { return nil }
        let cursor = operation.undo(content: &content)
        redoHistory.append(operation)
        return (cursor, operation.semanticChange)
    }
    
    func redo(content: inout String) -> (cursor: Int, change: SemanticChange?)? {
        guard let operation = redoHistory.popLast() else { return nil }
        let cursor = operation.redo(content: &content)
        undoHistory.append(operation)
        return (cursor, operation.semanticChange)
    }
    
    func clear() {
        undoHistory.removeAll()
        redoHistory.removeAll()
    }
}

