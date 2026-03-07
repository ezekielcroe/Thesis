// CompSplitView.swift — Thesis
// Side-by-side diff renderer with synchronized scrolling, alignment padding, and strikethroughs

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
        
        // 1. ADD THIS: Set the coordinator as the delegate
        splitView.delegate = context.coordinator
        
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
        
        // Synchronize Scrolling
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
        
        DispatchQueue.main.async {
            rightText.window?.makeFirstResponder(rightText)
            
            // 2. ADD THIS: Force the divider to the exact middle of the available space
            if splitView.bounds.width > 0 {
                splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)
            }
        }
        
        return splitView
    }
    
    func updateNSView(_ nsView: NSSplitView, context: Context) {
        guard let leftText = context.coordinator.leftText,
              let rightText = context.coordinator.rightText else { return }
        
        let layout = DiffRenderer.build(from: diffChanges)
        
        // Always update when diff changes arrive
        leftText.textStorage?.setAttributedString(layout.leftString)
        rightText.textStorage?.setAttributedString(layout.rightString)
        
        // Scroll to current change
        guard diffChanges.indices.contains(currentIndex) else { return }
        let currentChangeId = diffChanges[currentIndex].id
        
        if let ranges = layout.changeRanges[currentChangeId] {
            rightText.scrollRangeToVisible(ranges.right)
            
            DispatchQueue.main.async {
                if ranges.right.length > 0 {
                    rightText.showFindIndicator(for: ranges.right)
                }
                if ranges.left.length > 0 {
                    leftText.showFindIndicator(for: ranges.left)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
        
    // 3. REPLACE your Coordinator with this updated version
    class Coordinator: NSObject, NSSplitViewDelegate {
        weak var leftText: CompNSTextView?
        weak var rightText: CompNSTextView?
        var isSyncing: Bool = false
        
        // Prevent either pane from collapsing to 0 width
        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            return false
        }
        
        // Optional: Prevent the user from dragging the divider too far left
        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return 150
        }
        
        // Optional: Prevent the user from dragging the divider too far right
        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return splitView.bounds.width - 150
        }
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
        let placeholderAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor,
            .backgroundColor: NSColor.quaternaryLabelColor
        ]
        
        for change in diffs {
            let leftStart = leftStr.length
            let rightStart = rightStr.length
            
            switch change.type {
            case .unchanged:
                let text = change.text + "\n"
                leftStr.append(NSAttributedString(string: text, attributes: defaultAttrs))
                rightStr.append(NSAttributedString(string: text, attributes: defaultAttrs))
                
            case .deletion:
                var attrs = defaultAttrs
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = NSColor.systemRed
                attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.15)
                let text = change.text + "\n"
                leftStr.append(NSAttributedString(string: text, attributes: attrs))
                // FIX: Add placeholder on right side so lines stay aligned
                let placeholder = String(repeating: " ", count: min(change.text.count, 40)) + " [deleted]\n"
                rightStr.append(NSAttributedString(string: placeholder, attributes: placeholderAttrs))
                
            case .addition:
                if let wordDiffs = change.wordDiffs, !wordDiffs.isEmpty {
                    // 1. Build Left Side (Old Sentence granular diff)
                    let leftWords = wordDiffs.filter { $0.type == .unchanged || $0.type == .deletion }
                    for word in leftWords {
                        var lAttrs = defaultAttrs
                        if word.type == .deletion {
                            lAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                            lAttrs[.strikethroughColor] = NSColor.systemRed
                            lAttrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.15)
                        }
                        leftStr.append(NSAttributedString(string: word.text + " ", attributes: lAttrs))
                    }
                    
                    // 2. Build Right Side (New Sentence granular diff)
                    let rightWords = wordDiffs.filter { $0.type == .unchanged || $0.type == .addition }
                    for word in rightWords {
                        var rAttrs = defaultAttrs
                        if word.type == .addition {
                            let bgColor: NSColor = {
                                switch change.semanticType {
                                case .replaced: return .systemOrange
                                default:        return .systemGreen
                                }
                            }()
                            rAttrs[.backgroundColor] = bgColor.withAlphaComponent(0.2)
                        }
                        rightStr.append(NSAttributedString(string: word.text + " ", attributes: rAttrs))
                    }
                } else {
                    // Fallback: Handle Left Side (The "Old" version of the replaced text, if any)
                    if let oldText = change.oldText {
                        var lAttrs = defaultAttrs
                        lAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                        lAttrs[.strikethroughColor] = NSColor.systemRed
                        lAttrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.15)
                        leftStr.append(NSAttributedString(string: oldText + " ", attributes: lAttrs))
                    }
                    
                    // Fallback: Handle Right Side (The "New" version)
                    var rAttrs = defaultAttrs
                    let bgColor: NSColor = {
                        switch change.semanticType {
                        case .replaced: return .systemOrange
                        default:        return .systemGreen
                        }
                    }()
                    rAttrs[.backgroundColor] = bgColor.withAlphaComponent(0.2)
                    rightStr.append(NSAttributedString(string: change.text + " ", attributes: rAttrs))
                }
                
            case .moved:
                var attrs = defaultAttrs
                attrs[.backgroundColor] = NSColor.systemPurple.withAlphaComponent(0.2)
                let text = change.text + "\n"
                leftStr.append(NSAttributedString(string: text, attributes: defaultAttrs))
                rightStr.append(NSAttributedString(string: text, attributes: attrs))
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
