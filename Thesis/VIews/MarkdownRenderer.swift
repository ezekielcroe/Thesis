// MarkdownRenderer.swift — Thesis
// Turns the document's Markdown into formatted text, for the preview and for PDF export.
// Uses Foundation's own CommonMark parser (AttributedString(markdown:)), so no packages
// are needed. Supported: headings, paragraphs, bold, italic, strikethrough, inline code,
// code blocks, block quotes, bulleted and numbered (nested) lists, links, horizontal
// rules and simple tables. Images show their description text.

import AppKit

enum MarkdownRenderer {

    struct Style {
        var textColor: NSColor
        var secondaryColor: NSColor
        var accentColor: NSColor
        var codeBackground: NSColor
        var baseSize: CGFloat

        /// Follows light/dark mode.
        static let screen = Style(textColor: .textColor,
                                  secondaryColor: .secondaryLabelColor,
                                  accentColor: .linkColor,
                                  codeBackground: NSColor.quaternaryLabelColor.withAlphaComponent(0.25),
                                  baseSize: 16)

        /// Black on white whatever the app's appearance, sized for paper.
        static let print = Style(textColor: .black,
                                 secondaryColor: NSColor(white: 0.35, alpha: 1),
                                 accentColor: NSColor(srgbRed: 0.1, green: 0.3, blue: 0.7, alpha: 1),
                                 codeBackground: NSColor(white: 0.93, alpha: 1),
                                 baseSize: 12)
    }

    static func render(title: String?, markdown: String, style: Style) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.paragraphSpacing = style.baseSize * 1.2
            result.append(NSAttributedString(string: title, attributes: [
                .font: serif(size: style.baseSize * 1.8, bold: true),
                .foregroundColor: style.textColor,
                .paragraphStyle: titleStyle,
            ]))
        }

        let source = MarkdownSource.normalizedForRendering(markdown)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible,
            languageCode: nil
        )
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(NSAttributedString(string: markdown, attributes: [
                .font: serif(size: style.baseSize, bold: false),
                .foregroundColor: style.textColor,
            ]))
            return result
        }

        var previousLeaf: Int?
        var previousListItem: Int?
        var previousRow: Int?

        for run in parsed.runs {
            let block = BlockInfo(run.presentationIntent)
            var text = String(parsed[run.range].characters)

            // Separate blocks: a new table cell in the same row gets a tab, anything else a line break.
            if let leaf = block.leafIdentity, leaf != previousLeaf {
                if previousLeaf != nil || result.length > 0 {
                    let sameRow = block.rowIdentity != nil && block.rowIdentity == previousRow
                    result.append(NSAttributedString(string: sameRow ? "\t" : "\n",
                                                     attributes: [.font: serif(size: style.baseSize, bold: false)]))
                }
                // First paragraph of a list item: put its bullet or number in front.
                if let item = block.listItem, item.identity != previousListItem {
                    let marker = block.isOrderedList ? "\(item.ordinal)." : "•"
                    result.append(NSAttributedString(string: marker + "\t", attributes: [
                        .font: serif(size: style.baseSize, bold: false),
                        .foregroundColor: style.secondaryColor,
                        .paragraphStyle: paragraphStyle(for: block, style: style),
                    ]))
                    previousListItem = item.identity
                }
                previousLeaf = leaf
                previousRow = block.rowIdentity
            }

            if block.isThematicBreak {
                text = "⁂"
            }
            if block.isCodeBlock, text.hasSuffix("\n") {
                text.removeLast()
            }

            result.append(NSAttributedString(string: text,
                                             attributes: attributes(for: run, block: block, style: style)))
        }
        return result
    }

    // MARK: - Block structure

    /// What a run sits inside, worked out by kind rather than by position, so it doesn't
    /// depend on the order PresentationIntent lists its components in.
    private struct BlockInfo {
        var leafIdentity: Int?
        var headerLevel: Int?
        var isCodeBlock = false
        var isThematicBreak = false
        var isHeaderRow = false
        var rowIdentity: Int?
        var quoteDepth = 0
        var listDepth = 0
        var listItem: (identity: Int, ordinal: Int)?
        var isOrderedList = false
        var isCentered: Bool { isThematicBreak }

        init(_ intent: PresentationIntent?) {
            var innermostList: (identity: Int, ordered: Bool)?
            for component in intent?.components ?? [] {
                switch component.kind {
                case .paragraph:
                    leafIdentity = leafIdentity ?? component.identity
                case .header(let level):
                    leafIdentity = component.identity
                    headerLevel = level
                case .codeBlock:
                    leafIdentity = component.identity
                    isCodeBlock = true
                case .thematicBreak:
                    leafIdentity = component.identity
                    isThematicBreak = true
                case .tableCell:
                    leafIdentity = component.identity
                case .tableHeaderRow:
                    rowIdentity = component.identity
                    isHeaderRow = true
                case .tableRow:
                    rowIdentity = component.identity
                case .blockQuote:
                    quoteDepth += 1
                case .orderedList, .unorderedList:
                    listDepth += 1
                    let ordered: Bool
                    if case .orderedList = component.kind { ordered = true } else { ordered = false }
                    // Identities grow in document order, so the nested (innermost) list is the largest.
                    if innermostList == nil || component.identity > innermostList!.identity {
                        innermostList = (component.identity, ordered)
                    }
                case .listItem(let ordinal):
                    if listItem == nil || component.identity > listItem!.identity {
                        listItem = (component.identity, ordinal)
                    }
                default:
                    break
                }
            }
            isOrderedList = innermostList?.ordered ?? false
        }
    }

    // MARK: - Attributes

    private static func attributes(for run: AttributedString.Runs.Run, block: BlockInfo,
                                   style: Style) -> [NSAttributedString.Key: Any] {
        var size = style.baseSize
        var bold = false
        if let level = block.headerLevel {
            size *= [1.6, 1.35, 1.18, 1.05, 1.0, 1.0][min(max(level, 1), 6) - 1]
            bold = true
        }
        if block.isHeaderRow { bold = true }

        let inline = run.inlinePresentationIntent ?? []
        var font: NSFont
        if block.isCodeBlock || inline.contains(.code) {
            font = NSFont.monospacedSystemFont(ofSize: size * 0.88, weight: bold ? .semibold : .regular)
        } else {
            font = serif(size: size, bold: bold || inline.contains(.stronglyEmphasized))
            if inline.contains(.emphasized) || block.quoteDepth > 0 {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
        }

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: block.quoteDepth > 0 || block.isThematicBreak ? style.secondaryColor : style.textColor,
            .paragraphStyle: paragraphStyle(for: block, style: style),
        ]
        if block.isCodeBlock || inline.contains(.code) {
            attrs[.backgroundColor] = style.codeBackground
        }
        if inline.contains(.strikethrough) {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link = run.link {
            attrs[.link] = link
            attrs[.foregroundColor] = style.accentColor
        }
        return attrs
    }

    private static func paragraphStyle(for block: BlockInfo, style: Style) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        let base = style.baseSize
        p.lineSpacing = base * 0.25
        p.paragraphSpacing = block.isCodeBlock ? base * 0.2 : base * 0.6
        if block.headerLevel != nil {
            p.paragraphSpacingBefore = base * 0.6
        }
        if block.isCentered {
            p.alignment = .center
        }

        let indentStep = base * 1.5
        var indent = CGFloat(block.quoteDepth) * indentStep
        if block.listDepth > 0 {
            indent += CGFloat(block.listDepth - 1) * indentStep
            let textStart = indent + indentStep
            p.firstLineHeadIndent = indent
            p.headIndent = textStart
            p.tabStops = [NSTextTab(textAlignment: .left, location: textStart)]
        } else if block.rowIdentity != nil {
            p.firstLineHeadIndent = indent
            p.headIndent = indent
            p.tabStops = (1...8).map { NSTextTab(textAlignment: .left, location: indent + CGFloat($0) * base * 9) }
        } else {
            p.firstLineHeadIndent = indent
            p.headIndent = indent
        }
        return p
    }

    static func serif(size: CGFloat, bold: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
}
