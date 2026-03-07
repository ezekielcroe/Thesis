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
