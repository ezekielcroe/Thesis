// Document.swift — Thesis
// A piece of writing: its current text, its snapshot history, the darlings cut from
// it, notes on it, and the writer's reasons for changes.

import Foundation
import Combine

final class Document: ObservableObject, Identifiable, Codable, Equatable {
    private(set) var id: UUID
    @Published var title: String
    /// The text right now. While editing, the text view is the source of truth and
    /// writes every change here.
    @Published var content: String
    /// Oldest first.
    @Published private(set) var snapshots: [Snapshot]
    /// Oldest first.
    @Published private(set) var darlings: [Darling]
    @Published var notes: [Note]
    /// Why a change was made, keyed by `ProseChange.fingerprint`.
    @Published private(set) var reasons: [String: String]
    @Published var lastModified: Date

    /// Snapshots never change, so diffs between two of them can be cached for good.
    private var diffCache: [String: [ProseChange]] = [:]

    /// Automatic snapshots beyond this many are thinned to one per day. Named ones are never pruned.
    static let recentAutomaticSnapshotsKept = 50

    init(title: String = "Untitled") {
        id = UUID()
        self.title = title
        content = ""
        snapshots = []
        darlings = []
        notes = []
        reasons = [:]
        lastModified = Date()
    }

    static func == (lhs: Document, rhs: Document) -> Bool { lhs.id == rhs.id }

    /// Gives an imported copy its own identity, so it can sit alongside the original.
    func assignNewIdentity() {
        id = UUID()
    }

    // MARK: - Snapshots

    var latestSnapshot: Snapshot? { snapshots.last }
    var latestNamedSnapshot: Snapshot? { snapshots.last(where: { !$0.isAutomatic }) }
    var hasUnsnapshottedChanges: Bool { content != (latestSnapshot?.content ?? "") }

    /// Captures the current text. Automatic snapshots (no name) are skipped when nothing
    /// changed; naming an unchanged automatic snapshot promotes it instead of duplicating it.
    @discardableResult
    func takeSnapshot(name: String? = nil, note: String = "") -> Snapshot? {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let snapshotName: String? = trimmedName.isEmpty ? nil : trimmedName

        if let latest = snapshots.last, latest.content == content {
            guard snapshotName != nil else { return nil }
            if latest.isAutomatic {
                snapshots[snapshots.count - 1].name = snapshotName
                snapshots[snapshots.count - 1].note = note
                lastModified = Date()
                return snapshots.last
            }
        }
        if snapshots.isEmpty && content.isEmpty && snapshotName == nil { return nil }

        collectDarlings(from: snapshots.last?.content ?? "", to: content, at: Date())
        let snapshot = Snapshot(content: content, name: snapshotName, note: note)
        snapshots.append(snapshot)
        pruneAutomaticSnapshots()
        lastModified = Date()
        return snapshot
    }

    func namedSnapshot(before snapshot: Snapshot) -> Snapshot? {
        guard let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) else { return nil }
        return snapshots[..<index].last(where: { !$0.isAutomatic })
    }

    /// Changes between two snapshots (`older == nil` means from an empty document).
    func changes(from older: Snapshot?, to newer: Snapshot) -> [ProseChange] {
        let key = "\(older?.id.uuidString ?? "start")>\(newer.id.uuidString)"
        if let cached = diffCache[key] { return cached }
        let result = ProseDiff.changes(from: older?.content ?? "", to: newer.content)
        diffCache[key] = result
        return result
    }

    /// What the writer has changed since their last named checkpoint.
    func changesSinceLastNamedSnapshot() -> [ProseChange] {
        ProseDiff.changes(from: latestNamedSnapshot?.content ?? "", to: content)
    }

    private func pruneAutomaticSnapshots() {
        let automatic = snapshots.indices.filter { snapshots[$0].isAutomatic }
        guard automatic.count > Self.recentAutomaticSnapshotsKept else { return }
        let older = automatic.dropLast(Self.recentAutomaticSnapshotsKept)
        var lastOfDay: [DateComponents: Int] = [:]
        let calendar = Calendar.current
        for i in older {
            lastOfDay[calendar.dateComponents([.year, .month, .day], from: snapshots[i].timestamp)] = i
        }
        let keep = Set(lastOfDay.values)
        let remove = Set(older.filter { !keep.contains($0) })
        guard !remove.isEmpty else { return }
        // Darlings were already collected when each snapshot was taken, so nothing is lost.
        snapshots = snapshots.enumerated().filter { !remove.contains($0.offset) }.map(\.element)
    }

    // MARK: - Darlings

    private func collectDarlings(from old: String, to new: String, at date: Date) {
        guard !old.isEmpty else { return }
        var known = Set(darlings.map { ProseDiff.normalize($0.text) })
        for change in ProseDiff.changes(from: old, to: new) {
            guard let lost = change.lostText else { continue }
            let key = ProseDiff.normalize(lost)
            guard !key.isEmpty, !known.contains(key) else { continue }
            known.insert(key)
            darlings.append(Darling(text: lost,
                                    replacedBy: change.kind == .rewritten ? change.after : nil,
                                    fingerprint: change.fingerprint,
                                    cutAt: date))
        }
    }

    private func rebuildDarlingsFromHistory() {
        darlings = []
        guard snapshots.count > 1 else { return }
        for i in 1..<snapshots.count {
            collectDarlings(from: snapshots[i - 1].content, to: snapshots[i].content, at: snapshots[i].timestamp)
        }
    }

    // MARK: - Reasons

    func reason(for fingerprint: String) -> String? { reasons[fingerprint] }

    func setReason(_ text: String, for fingerprint: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons[fingerprint] = nil
        } else {
            reasons[fingerprint] = text
        }
    }

    // MARK: - Notes

    func addNote(_ text: String, category: NoteCategory, range: NSRange) {
        let ns = content as NSString
        let safe = NSRange(location: min(range.location, ns.length),
                           length: min(range.length, ns.length - min(range.location, ns.length)))
        notes.append(Note(text: text, category: category, range: safe, anchorText: ns.substring(with: safe)))
    }

    func updateNote(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].text = text
        notes[i].updatedAt = Date()
    }

    func setResolved(_ id: UUID, _ resolved: Bool) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].resolved = resolved
        notes[i].updatedAt = Date()
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
    }

    /// Called for every edit to the text (typing, commands, undo, restore), in the
    /// coordinates before the edit, to keep notes attached to their words.
    func applyEdit(location: Int, removed: Int, inserted: Int, newText: String) {
        guard !notes.isEmpty else { return }
        let ns = newText as NSString
        let oldLength = ns.length - inserted + removed

        // Whole text replaced (restoring a snapshot): find each note's words again.
        if location == 0 && removed == oldLength && removed > 0 {
            var updated = notes
            for i in updated.indices {
                updated[i].range = NoteAnchor.find(updated[i].anchorText, in: ns, near: updated[i].location)
                    ?? NSRange(location: min(updated[i].location, ns.length), length: 0)
            }
            if updated != notes { notes = updated }
            return
        }

        var updated = notes
        for i in updated.indices {
            var range = NoteAnchor.adjust(updated[i].range, editLocation: location, removed: removed, inserted: inserted)
            // Detached notes reattach if their words come back (undo, put).
            if range.length == 0 && inserted > 0 && !updated[i].anchorText.isEmpty {
                let window = updated[i].anchorText.utf16Length
                let start = max(0, location - window)
                let end = min(ns.length, location + inserted + window)
                let found = ns.range(of: updated[i].anchorText, options: [],
                                     range: NSRange(location: start, length: end - start))
                if found.location != NSNotFound { range = found }
            }
            updated[i].range = range
        }
        if updated != notes { notes = updated }
    }

    private func reanchorLegacyNotes() {
        let ns = content as NSString
        for i in notes.indices {
            if notes[i].needsReanchor {
                notes[i].range = NoteAnchor.find(notes[i].anchorText, in: ns, near: notes[i].location)
                    ?? NSRange(location: min(notes[i].location, ns.length), length: 0)
                notes[i].needsReanchor = false
            } else if NSMaxRange(notes[i].range) > ns.length {
                notes[i].range = NSRange(location: min(notes[i].location, ns.length), length: 0)
            }
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, content, snapshots, darlings, notes, reasons, lastModified
        case currentContent, drafts, annotations   // earlier versions
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        content = try c.decodeIfPresent(String.self, forKey: .content)
            ?? c.decodeIfPresent(String.self, forKey: .currentContent) ?? ""
        // Earlier versions kept drafts on several branches; they become one timeline.
        let storedSnapshots = try c.decodeIfPresent([Snapshot].self, forKey: .snapshots)
            ?? c.decodeIfPresent([Snapshot].self, forKey: .drafts) ?? []
        snapshots = storedSnapshots.sorted { $0.timestamp < $1.timestamp }
        notes = try c.decodeIfPresent([Note].self, forKey: .notes)
            ?? c.decodeIfPresent([Note].self, forKey: .annotations) ?? []
        reasons = try c.decodeIfPresent([String: String].self, forKey: .reasons) ?? [:]
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
        let storedDarlings = try c.decodeIfPresent([Darling].self, forKey: .darlings)
        darlings = storedDarlings ?? []
        if storedDarlings == nil { rebuildDarlingsFromHistory() }
        reanchorLegacyNotes()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(snapshots, forKey: .snapshots)
        try c.encode(darlings, forKey: .darlings)
        try c.encode(notes, forKey: .notes)
        try c.encode(reasons, forKey: .reasons)
        try c.encode(lastModified, forKey: .lastModified)
    }
}
