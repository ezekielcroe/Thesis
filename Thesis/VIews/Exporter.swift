// Exporter.swift — Thesis
// Save/open panels for exporting and importing, and PDF rendering.
//
// If the app is sandboxed (the default for new Xcode projects), writing exports needs
// Signing & Capabilities → App Sandbox → File Access → User Selected File: Read/Write.

import AppKit
import UniformTypeIdentifiers

@MainActor
enum Exporter {
    static let archiveType = UTType(filenameExtension: "thesis", conformingTo: .json) ?? .json

    enum ExportError: LocalizedError {
        case pdfFailed
        var errorDescription: String? { "The PDF couldn't be created." }
    }

    // MARK: - Export

    static func export(_ document: Document, as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.title = "Export “\(document.title.isEmpty ? "Untitled" : document.title)”"
        panel.nameFieldStringValue = DocumentExport.suggestedFileName(title: document.title, format: format)
        panel.allowedContentTypes = [contentType(for: format)]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .plainText:
                try DocumentExport.plainText(document).write(to: url, atomically: true, encoding: .utf8)
            case .markdown:
                try DocumentExport.markdown(document).write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                try writePDF(document, to: url)
            case .archive:
                try DocumentExport.archiveData([document]).write(to: url, options: .atomic)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func backUpAll(_ documents: [Document]) {
        let panel = NSSavePanel()
        panel.title = "Back Up All Documents"
        let day = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Thesis Backup \(day).thesis"
        panel.allowedContentTypes = [archiveType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DocumentExport.archiveData(documents).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Import

    /// Asks for a .thesis archive (or a documents.json) and reads it.
    static func chooseArchive() -> [Document]? {
        let panel = NSOpenPanel()
        panel.title = "Import Thesis Archive"
        panel.allowedContentTypes = [archiveType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try DocumentExport.documents(fromArchive: Data(contentsOf: url))
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    static func askAboutConflict(_ document: Document) -> ImportChoice {
        let alert = NSAlert()
        alert.messageText = "“\(document.title)” is already in your documents"
        alert.informativeText = "Keep both, or replace your current copy with the archived one? Replacing discards the current copy's text and history."
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        default: return .skip
        }
    }

    // MARK: - PDF

    private static func contentType(for format: ExportFormat) -> UTType {
        switch format {
        case .plainText: return .plainText
        case .markdown: return UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
        case .pdf: return .pdf
        case .archive: return archiveType
        }
    }

    /// Lays the text out on pages with the system's print pagination, saving to `url`.
    private static func writePDF(_ document: Document, to url: URL) throws {
        let printInfo = NSPrintInfo(dictionary: [.jobSavingURL: url])
        printInfo.jobDisposition = .save
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.textStorage?.setAttributedString(attributedText(for: document))
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
            let height = layoutManager.usedRect(for: container).height
            textView.frame = NSRect(x: 0, y: 0, width: width, height: max(height, 1))
        }

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw ExportError.pdfFailed }
    }

    /// Black on white whatever the app's appearance, so PDFs print correctly in dark mode.
    private static func attributedText(for document: Document) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.paragraphSpacing = 18
            result.append(NSAttributedString(string: title + "\n", attributes: [
                .font: serif(size: 20, bold: true),
                .foregroundColor: NSColor.black,
                .paragraphStyle: titleStyle,
            ]))
        }

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 3
        bodyStyle.paragraphSpacing = 9
        let paragraphs = TextUnits(document.content).paragraphs.map(\.text)
        result.append(NSAttributedString(string: paragraphs.joined(separator: "\n"), attributes: [
            .font: serif(size: 12, bold: false),
            .foregroundColor: NSColor.black,
            .paragraphStyle: bodyStyle,
        ]))
        return result
    }

    private static func serif(size: CGFloat, bold: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
}
