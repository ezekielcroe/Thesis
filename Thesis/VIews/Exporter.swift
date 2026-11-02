// Exporter.swift — Thesis
// Save/open panels for exporting and importing, and PDF rendering.
//
// If the app is sandboxed (the default for new Xcode projects), writing exports needs
// Signing & Capabilities → App Sandbox → File Access → User Selected File: Read/Write.

import AppKit
import UniformTypeIdentifiers

@MainActor
enum Exporter {
    /// Declared in Info.plist (UTExportedTypeDeclarations), which is what lets Finder
    /// show "Thesis Archive" and open these files in Thesis on double-click.
    static let archiveType = UTType(exportedAs: "com.thesis.app.archive", conformingTo: .json)

    /// Files opened recently, so a file that reaches us by two routes is imported once.
    private static var recentlyOpened: [URL: Date] = [:]

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
                try writePDF(title: document.title, markdown: document.content, to: url)
            case .word:
                try writeWord(title: document.title, markdown: document.content, to: url)
            case .archive:
                try DocumentExport.archiveData([document]).write(to: url, options: .atomic)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Statistics tables

    /// Puts the table on the clipboard as HTML (Word and Pages paste a real table) and as
    /// tab-separated text (spreadsheets split it into cells).
    static func copy(_ table: StatisticsTable) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let tsv = table.tsv()
        pasteboard.setString(table.html(), forType: .html)
        pasteboard.setString(tsv, forType: NSPasteboard.PasteboardType("public.utf8-tab-separated-values-text"))
        pasteboard.setString(tsv, forType: .string)
    }

    static func saveCSV(_ table: StatisticsTable, documentTitle: String) {
        let panel = NSSavePanel()
        panel.title = "Save Statistics as CSV"
        let base = DocumentExport.suggestedFileName(title: documentTitle, format: .plainText)
            .replacingOccurrences(of: ".txt", with: "")
        panel.nameFieldStringValue = "\(base) statistics.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // A byte-order mark lets Excel recognise UTF-8 (accents, curly quotes).
            try ("\u{FEFF}" + table.csv()).write(to: url, atomically: true, encoding: .utf8)
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

    /// Imports archives opened from Finder (double-click, Open With, dropping on the Dock icon).
    static func open(_ urls: [URL], into manager: DocumentManager) {
        let now = Date()
        recentlyOpened = recentlyOpened.filter { now.timeIntervalSince($0.value) < 3 }
        for url in urls where url.isFileURL {
            let key = url.standardizedFileURL
            guard recentlyOpened[key] == nil else { continue }
            recentlyOpened[key] = now
            do {
                let ext = url.pathExtension.lowercased()
                if DocumentImport.archiveExtensions.contains(ext) {
                    let documents = try DocumentExport.documents(fromArchive: Data(contentsOf: url))
                    manager.importDocuments(documents, resolve: askAboutConflict)
                } else {
                    manager.importDocuments([try importFile(url)], resolve: askAboutConflict)
                }
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "“\(url.lastPathComponent)” couldn't be opened"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// File ▸ Open…: Thesis archives, plus text, Markdown and Word-type documents.
    static func showOpenPanel(into manager: DocumentManager) {
        let panel = NSOpenPanel()
        panel.title = "Open"
        panel.message = "Choose Thesis archives, or text, Markdown, Word, RTF or OpenDocument files to import."
        panel.allowedContentTypes = openableTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        open(panel.urls, into: manager)
    }

    /// A text, Markdown or rich-text file as a new document, starting with an "Imported"
    /// snapshot so its evolution log begins with the original.
    static func importFile(_ url: URL) throws -> Document {
        let ext = url.pathExtension.lowercased()
        let fallbackTitle = DocumentImport.title(fromFileName: url.lastPathComponent)
        let raw: String
        var isMarkdown = DocumentImport.markdownExtensions.contains(ext)
        var isRichText = false
        if DocumentImport.richTextExtensions.contains(ext) || ext == "pages" {
            raw = RichTextImporter.markdown(from: try RichTextImporter.read(url))
            isMarkdown = true
            isRichText = true
        } else if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            raw = utf8
        } else {
            // Not UTF-8: let Foundation detect the encoding (e.g. older Windows or Mac text).
            var encoding = String.Encoding.utf8
            raw = try String(contentsOf: url, usedEncoding: &encoding)
        }
        let prepared = DocumentImport.prepare(raw, isMarkdown: isMarkdown, fallbackTitle: fallbackTitle,
                                              unwrap: !isRichText)
        let document = Document(title: prepared.title)
        document.content = prepared.content
        document.takeSnapshot(name: "Imported", note: "From “\(url.lastPathComponent)”")
        return document
    }

    // MARK: - Evolution log

    static func exportEvolutionLog(_ document: Document, as format: EvolutionLogFormat) {
        let panel = NSSavePanel()
        let name = document.title.isEmpty ? "Untitled" : document.title
        panel.title = "Export Evolution Log of “\(name)”"
        let base = DocumentExport.suggestedFileName(title: document.title, format: .plainText)
            .replacingOccurrences(of: ".txt", with: "")
        panel.nameFieldStringValue = "\(base) evolution.\(format.fileExtension)"
        switch format {
        case .markdown:
            panel.allowedContentTypes = [UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText]
        case .pdf: panel.allowedContentTypes = [.pdf]
        case .word: panel.allowedContentTypes = [wordType]
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let markdown = EvolutionReport.markdown(for: document)
        do {
            switch format {
            case .markdown: try markdown.write(to: url, atomically: true, encoding: .utf8)
            case .pdf: try writePDF(title: nil, markdown: markdown, to: url)
            case .word: try writeWord(title: nil, markdown: markdown, to: url)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Word document from the same formatted text as the PDF (macOS writes .docx natively).
    private static func writeWord(title: String?, markdown: String, to url: URL) throws {
        let attributed = MarkdownRenderer.render(title: title, markdown: markdown, style: .print)
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        try data.write(to: url, options: .atomic)
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
        case .word: return wordType
        case .archive: return archiveType
        }
    }

    static let wordType = UTType("org.openxmlformats.wordprocessingml.document")
        ?? UTType(filenameExtension: "docx") ?? .data

    /// Everything File ▸ Open… accepts.
    static var openableTypes: [UTType] {
        var types: [UTType] = [archiveType, .json, .plainText, wordType, .rtf, .rtfd, .html]
        for identifier in ["net.daringfireball.markdown", "com.microsoft.word.doc", "org.oasis-open.opendocument.text"] {
            if let type = UTType(identifier) { types.append(type) }
        }
        for ext in ["md", "markdown"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    /// Lays the text out on pages with the system's print pagination, saving to `url`.
    private static func writePDF(title: String?, markdown: String, to url: URL) throws {
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
        textView.textStorage?.setAttributedString(
            MarkdownRenderer.render(title: title, markdown: markdown, style: .print)
        )
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
}

// MARK: - Name prompt

/// A standard AppKit dialog with a text field. Used instead of a SwiftUI `.alert`
/// because alerts inside the split view didn't reliably appear on macOS.
@MainActor
enum NamePrompt {
    /// Returns the entered text, or nil if cancelled or left empty.
    static func ask(title: String, message: String, initialValue: String, confirmTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)   // first button: Return
        alert.addButton(withTitle: "Cancel")       // Escape

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = initialValue
        field.placeholderString = "Title"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
