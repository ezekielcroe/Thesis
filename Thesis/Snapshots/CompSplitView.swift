// CompSplitView.swift — Thesis
// Side-by-side diff renderer with synchronized scrolling and strikethroughs

import SwiftUI
import AppKit

struct CompSplitView: NSViewRepresentable {
    let diffChanges: [DiffChange]
    let currentIndex: Int
    let onKeyPress: (String, NSEvent.ModifierFlags) -> Void
    
    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        
        // Left Pane (Old Draft)
        let leftScroll = NSScrollView()
        leftScroll.hasVerticalScroller = true
        let leftText = CompNSTextView()
        leftText.isEditable = false
        leftText.textContainerInset = NSSize(width: 20, height: 20)
        leftText.onKeyPress = onKeyPress
        leftScroll.documentView = leftText
        
        // Right Pane (New Draft)
        let rightScroll = NSScrollView()
        rightScroll.hasVerticalScroller = true
        let rightText = CompNSTextView()
        rightText.isEditable = false
        rightText.textContainerInset = NSSize(width: 20, height: 20)
        rightText.onKeyPress = onKeyPress
        rightScroll.documentView = rightText
        
        splitView.addArrangedSubview(leftScroll)
        splitView.addArrangedSubview(rightScroll)
        
        // Synchronize Scrolling (with guard to prevent feedback loop)
        let coordinator = context.coordinator
        leftScroll.contentView.postsBoundsChangedNotifications = true
        rightScroll.contentView.postsBoundsChangedNotifications = true
        
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: leftScroll.contentView,
            queue: .main
        ) { [weak rightScroll, weak coordinator] _ in
            guard let rightScroll = rightScroll, let coordinator = coordinator else { return }
            guard !coordinator.isSyncing else { return }
            coordinator.isSyncing = true
            let point = leftScroll.contentView.bounds.origin
            rightScroll.contentView.scroll(to: point)
            coordinator.isSyncing = false
        }
        
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: rightScroll.contentView,
            queue: .main
        ) { [weak leftScroll, weak coordinator] _ in
            guard let leftScroll = leftScroll, let coordinator = coordinator else { return }
            guard !coordinator.isSyncing else { return }
            coordinator.isSyncing = true
            let point = rightScroll.contentView.bounds.origin
            leftScroll.contentView.scroll(to: point)
            coordinator.isSyncing = false
        }
        
        coordinator.leftText = leftText
        coordinator.rightText = rightText
        
        return splitView
    }
    
    func updateNSView(_ nsView: NSSplitView, context: Context) {
        guard let leftText = context.coordinator.leftText,
              let rightText = context.coordinator.rightText else { return }
        
        // 1. Build the Rich Text
        let layout = DiffRenderer.build(from: diffChanges)
        
        // Only update text if it changed to prevent scrolling resets
        if leftText.string != layout.leftString.string {
            leftText.textStorage?.setAttributedString(layout.leftString)
            rightText.textStorage?.setAttributedString(layout.rightString)
        }
        
        // 2. Scroll to current change if 'n' or 'p' was pressed
        guard diffChanges.indices.contains(currentIndex) else { return }
        let currentChangeId = diffChanges[currentIndex].id
        
        if let ranges = layout.changeRanges[currentChangeId] {
            // Scroll right text to view, and flash the native AppKit find indicator
            rightText.scrollRangeToVisible(ranges.right)
            
            // Debounce the find indicator so it doesn't spam
            DispatchQueue.main.async {
                rightText.showFindIndicator(for: ranges.right)
                leftText.showFindIndicator(for: ranges.left)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        weak var leftText: CompNSTextView?
        weak var rightText: CompNSTextView?
        var isSyncing: Bool = false  // Prevents scroll observer feedback loop
    }
}

// MARK: - Key-Catching Text View

class CompNSTextView: NSTextView {
    var onKeyPress: ((String, NSEvent.ModifierFlags) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        onKeyPress?(chars, event.modifierFlags)
    }
    
    // Prevent mouse clicks from messing with the selection state while in diff mode
    override func mouseDown(with event: NSEvent) {}
}

// MARK: - Diff String Builder

struct DiffLayout {
    let leftString: NSAttributedString
    let rightString: NSAttributedString
    let changeRanges: [UUID: (left: NSRange, right: NSRange)]
}

class DiffRenderer {
    static func build(from diffs: [DiffChange]) -> DiffLayout {
        let leftStr = NSMutableAttributedString()
        let rightStr = NSMutableAttributedString()
        var changeRanges: [UUID: (left: NSRange, right: NSRange)] = [:]
        
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
        
        for change in diffs {
            let leftStart = leftStr.length
            let rightStart = rightStr.length
            
            switch change.type {
            case .unchanged:
                leftStr.append(NSAttributedString(string: change.text + " ", attributes: defaultAttrs))
                rightStr.append(NSAttributedString(string: change.text + " ", attributes: defaultAttrs))
                
            case .deletion:
                var attrs = defaultAttrs
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = NSColor.systemRed
                attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.15)
                leftStr.append(NSAttributedString(string: change.text + " ", attributes: attrs))
                // Right side gets nothing; the text is gone.
                
            case .addition:
                // Handle Left Side (The "Old" version of the replaced text, if any)
                if let oldText = change.oldText {
                    var lAttrs = defaultAttrs
                    lAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    lAttrs[.strikethroughColor] = NSColor.systemRed
                    lAttrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.15)
                    leftStr.append(NSAttributedString(string: oldText + " ", attributes: lAttrs))
                }
                
                // Handle Right Side (The "New" version)
                var rAttrs = defaultAttrs
                let bgColor: NSColor = {
                    switch change.semanticType {
                    case .refined:  return .systemBlue
                    case .replaced: return .systemOrange
                    default:        return .systemGreen
                    }
                }()
                rAttrs[.backgroundColor] = bgColor.withAlphaComponent(0.2)
                rightStr.append(NSAttributedString(string: change.text + " ", attributes: rAttrs))
                
            case .moved:
                var attrs = defaultAttrs
                attrs[.backgroundColor] = NSColor.systemPurple.withAlphaComponent(0.2)
                // Left side gets normal text, right gets purple to indicate it arrived here
                leftStr.append(NSAttributedString(string: change.text + " ", attributes: defaultAttrs))
                rightStr.append(NSAttributedString(string: change.text + " ", attributes: attrs))
            }
            
            let leftEnd = leftStr.length
            let rightEnd = rightStr.length
            
            changeRanges[change.id] = (
                left: NSRange(location: leftStart, length: max(0, leftEnd - leftStart)),
                right: NSRange(location: rightStart, length: max(0, rightEnd - rightStart))
            )
        }
        
        return DiffLayout(leftString: leftStr, rightString: rightStr, changeRanges: changeRanges)
    }
}
