import Foundation

struct UndoCommand {
    let beforeContent: String
    let afterContent: String
    let cursorBefore: Int
    let cursorAfter: Int
    
    func undo(in content: inout String) -> Int? {
        content = beforeContent
        return cursorBefore
    }
}

class UndoStack {
    private var commands: [UndoCommand] = []
    private let maxSize = 10
    
    func push(_ command: UndoCommand) {
        commands.append(command)
        if commands.count > maxSize {
            commands.removeFirst()
        }
    }
    
    func pop() -> UndoCommand? {
        guard !commands.isEmpty else { return nil }
        return commands.removeLast()
    }
    
    func clear() {
        commands.removeAll()
    }
    
    var canUndo: Bool {
        return !commands.isEmpty
    }
    
    var count: Int {
        return commands.count
    }
}
