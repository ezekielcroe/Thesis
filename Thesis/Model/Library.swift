// Library.swift — Thesis
// Grouping documents in the sidebar. Three levels at most:
//
//     Shelf  ▸  Project  ▸  Document
//
// A project is a body of work made of several documents: a thesis, a book, a screenplay,
// a paper (its documents might be chapters, scenes or sections). A shelf holds projects.
// Documents can sit at any level: on their own, on a shelf, or in a project. Projects can
// be on a shelf or on their own; shelves are always at the top.
//
// The level names appear only in menus; each group has the name the writer gives it. To
// call them something else (Sheaf and Book, say), change `displayName` below.

import Foundation

struct LibraryGroup: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case shelf, project

        var displayName: String {
            switch self {
            case .shelf: return "Shelf"
            case .project: return "Project"
            }
        }

        var icon: String {
            switch self {
            case .shelf: return "books.vertical"
            case .project: return "folder"
            }
        }
    }

    let id: UUID
    var name: String
    let kind: Kind
    /// For a project: the shelf it is on, or nil at the top level. Always nil for a shelf.
    var parentID: UUID?
    var isCollapsed: Bool

    init(name: String, kind: Kind, parentID: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.parentID = kind == .shelf ? nil : parentID
        self.isCollapsed = false
    }
}

enum GroupExportFormat: String, CaseIterable, Identifiable {
    case plainText = "txt"
    case markdown = "md"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .plainText: return "As Text Files (.txt)…"
        case .markdown: return "As Markdown Files (.md)…"
        }
    }
}

/// Tree logic over the flat lists the app stores. Order everywhere is the order of the
/// `documents` and `groups` arrays.
enum Library {

    enum Row: Identifiable {
        case group(LibraryGroup, depth: Int)
        case document(Document, depth: Int)

        var id: String {
            switch self {
            case .group(let group, _): return "group-\(group.id.uuidString)"
            case .document(let document, _): return "document-\(document.id.uuidString)"
            }
        }
    }

    /// The group a document is really in: nil if its group no longer exists.
    static func groupID(of document: Document, in groups: [LibraryGroup]) -> UUID? {
        guard let id = document.groupID, groups.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    static func documents(in groupID: UUID?, documents: [Document], groups: [LibraryGroup]) -> [Document] {
        documents.filter { self.groupID(of: $0, in: groups) == groupID }
    }

    static func shelves(_ groups: [LibraryGroup]) -> [LibraryGroup] {
        groups.filter { $0.kind == .shelf }
    }

    /// Projects on a shelf, or (nil) projects at the top level. A project whose shelf no
    /// longer exists counts as top level.
    static func projects(onShelf shelfID: UUID?, groups: [LibraryGroup]) -> [LibraryGroup] {
        let shelfIDs = Set(shelves(groups).map(\.id))
        return groups.filter { group in
            guard group.kind == .project else { return false }
            let parent = group.parentID.flatMap { shelfIDs.contains($0) ? $0 : nil }
            return parent == shelfID
        }
    }

    /// Everything in a group, including the documents of a shelf's projects.
    static func allDocuments(in group: LibraryGroup, documents: [Document], groups: [LibraryGroup]) -> [Document] {
        var result = self.documents(in: group.id, documents: documents, groups: groups)
        if group.kind == .shelf {
            for project in projects(onShelf: group.id, groups: groups) {
                result += self.documents(in: project.id, documents: documents, groups: groups)
            }
        }
        return result
    }

    /// The sidebar, top to bottom: shelves (each with its projects, then its own
    /// documents), then top-level projects, then top-level documents. Collapsed groups
    /// hide what's inside them.
    static func rows(documents: [Document], groups: [LibraryGroup]) -> [Row] {
        var rows: [Row] = []
        func addProject(_ project: LibraryGroup, depth: Int) {
            rows.append(.group(project, depth: depth))
            guard !project.isCollapsed else { return }
            for document in self.documents(in: project.id, documents: documents, groups: groups) {
                rows.append(.document(document, depth: depth + 1))
            }
        }
        for shelf in shelves(groups) {
            rows.append(.group(shelf, depth: 0))
            guard !shelf.isCollapsed else { continue }
            for project in projects(onShelf: shelf.id, groups: groups) { addProject(project, depth: 1) }
            for document in self.documents(in: shelf.id, documents: documents, groups: groups) {
                rows.append(.document(document, depth: 1))
            }
        }
        for project in projects(onShelf: nil, groups: groups) { addProject(project, depth: 0) }
        for document in self.documents(in: nil, documents: documents, groups: groups) {
            rows.append(.document(document, depth: 0))
        }
        return rows
    }

    /// Where a document can be moved: every shelf and project, as "Shelf" or "Shelf ▸ Project".
    static func destinations(_ groups: [LibraryGroup]) -> [(title: String, id: UUID)] {
        var result: [(title: String, id: UUID)] = []
        for shelf in shelves(groups) {
            result.append((shelf.name, shelf.id))
            for project in projects(onShelf: shelf.id, groups: groups) {
                result.append(("\(shelf.name) ▸ \(project.name)", project.id))
            }
        }
        for project in projects(onShelf: nil, groups: groups) {
            result.append((project.name, project.id))
        }
        return result
    }

    // MARK: - Exporting a group as a folder of files

    struct GroupExport: Equatable {
        struct File: Equatable {
            /// Path inside the exported folder, e.g. "Part One/02 The Storm.md".
            let path: String
            let contents: String
        }
        /// Name of the folder to create.
        let folderName: String
        /// Sub-folders to create (so an empty project still appears).
        let directories: [String]
        let files: [File]
    }

    /// A shelf becomes a folder with a sub-folder per project; a project becomes a folder.
    /// Documents are numbered ("01 Title.md") so they stay in their sidebar order in Finder.
    static func export(_ group: LibraryGroup, documents: [Document], groups: [LibraryGroup],
                       format: GroupExportFormat) -> GroupExport {
        var directories: [String] = []
        var files: [GroupExport.File] = []

        func addDocuments(_ list: [Document], under folder: String?) {
            let digits = max(2, String(list.count).count)
            for (index, document) in list.enumerated() {
                let number = String(repeating: "0", count: digits - String(index + 1).count) + String(index + 1)
                let name = "\(number) \(DocumentExport.fileBaseName(document.title)).\(format.rawValue)"
                let contents = format == .markdown ? DocumentExport.markdown(document) : DocumentExport.plainText(document)
                files.append(GroupExport.File(path: folder.map { "\($0)/\(name)" } ?? name, contents: contents))
            }
        }

        if group.kind == .shelf {
            var used = Set<String>()
            for project in projects(onShelf: group.id, groups: groups) {
                var folder = DocumentExport.fileBaseName(project.name)
                var suffix = 2
                while used.contains(folder.lowercased()) {
                    folder = "\(DocumentExport.fileBaseName(project.name)) \(suffix)"
                    suffix += 1
                }
                used.insert(folder.lowercased())
                directories.append(folder)
                addDocuments(self.documents(in: project.id, documents: documents, groups: groups), under: folder)
            }
        }
        addDocuments(self.documents(in: group.id, documents: documents, groups: groups), under: nil)

        return GroupExport(folderName: DocumentExport.fileBaseName(group.name), directories: directories, files: files)
    }
}
