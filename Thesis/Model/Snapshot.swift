// Snapshot.swift — Thesis
// A saved version of a document's text, the darlings cut from it, and when snapshots are taken.

import Foundation

struct Snapshot: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let timestamp: Date
    /// nil for automatic snapshots; named snapshots are the writer's own checkpoints.
    var name: String?
    /// What changed in the writer's thinking, in their words (optional).
    var note: String

    var isAutomatic: Bool { name == nil }

    var displayName: String {
        name ?? "Automatic snapshot, \(timestamp.formatted(date: .abbreviated, time: .shortened))"
    }

    init(content: String, name: String? = nil, note: String = "") {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.name = name
        self.note = note
    }

    // Also reads the `Draft` records saved by earlier versions (they had `comment`).
    private enum CodingKeys: String, CodingKey { case id, content, timestamp, name, note, comment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        name = try c.decodeIfPresent(String.self, forKey: .name)
        note = try c.decodeIfPresent(String.self, forKey: .note)
            ?? c.decodeIfPresent(String.self, forKey: .comment) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(note, forKey: .note)
    }
}

/// Text that was cut or rewritten away, kept so nothing the writer wrote is ever lost.
struct Darling: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    /// For rewritten sentences, what replaced it.
    let replacedBy: String?
    let cutAt: Date
    /// The `ProseChange.fingerprint` of the change that removed it (to find its reason).
    let fingerprint: String

    init(text: String, replacedBy: String?, fingerprint: String, cutAt: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.replacedBy = replacedBy
        self.cutAt = cutAt
        self.fingerprint = fingerprint
    }
}

// MARK: - When snapshots are taken

enum SnapshotTrigger: String, CaseIterable, Identifiable {
    case pause, interval, manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pause: return "When I pause writing"
        case .interval: return "At regular intervals while I write"
        case .manual: return "Only when I save one"
        }
    }

    var detail: String {
        switch self {
        case .pause:
            return "A snapshot is taken after a short break in typing, and when you switch documents or quit."
        case .interval:
            return "A snapshot is taken on a fixed schedule while there are new changes, and when you switch documents or quit."
        case .manual:
            return "Nothing is captured automatically. Text you cut between saved snapshots won't reach Darlings."
        }
    }
}

enum SnapshotSettings {
    static let triggerKey = "snapshot.trigger"
    static let pauseKey = "snapshot.pauseSeconds"
    static let intervalKey = "snapshot.intervalMinutes"
    static let defaultPauseSeconds = 30
    static let defaultIntervalMinutes = 10

    struct Configuration: Equatable {
        var trigger: SnapshotTrigger
        var pauseSeconds: Int
        var intervalMinutes: Int
    }

    static var current: Configuration {
        let defaults = UserDefaults.standard
        let trigger = defaults.string(forKey: triggerKey).flatMap(SnapshotTrigger.init(rawValue:)) ?? .pause
        let pause = defaults.object(forKey: pauseKey) as? Int ?? defaultPauseSeconds
        let interval = defaults.object(forKey: intervalKey) as? Int ?? defaultIntervalMinutes
        return Configuration(trigger: trigger, pauseSeconds: max(5, pause), intervalMinutes: max(1, interval))
    }
}
