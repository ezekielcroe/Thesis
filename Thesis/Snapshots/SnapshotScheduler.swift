//
//  SnapshotScheduler.swift
//  Thesis
//
//  Created by Zhi Zheng Yeo on 2/11/26.
//


// SnapshotScheduler.swift — Thesis
// Takes automatic snapshots of one document according to the user's setting
// (Settings → "Take snapshots"): after a pause in typing, on an interval, or never.

import Foundation

final class SnapshotScheduler {
    private weak var document: Document?
    private var configuration = SnapshotSettings.current
    private var pauseTimer: Timer?
    private var intervalTimer: Timer?
    private var hasNewChanges = false
    private var defaultsObserver: NSObjectProtocol?

    init(document: Document) {
        self.document = document
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.settingsMayHaveChanged()
        }
    }

    deinit {
        stopTimers()
        if let observer = defaultsObserver { NotificationCenter.default.removeObserver(observer) }
    }

    func textDidChange() {
        hasNewChanges = true
        switch configuration.trigger {
        case .pause:
            pauseTimer?.invalidate()
            pauseTimer = makeTimer(after: TimeInterval(configuration.pauseSeconds), repeats: false)
        case .interval:
            if intervalTimer == nil {
                intervalTimer = makeTimer(after: TimeInterval(configuration.intervalMinutes * 60), repeats: true)
            }
        case .manual:
            break
        }
    }

    /// Called when the editor goes away (switching documents) and on quit.
    func flush() {
        if configuration.trigger != .manual { fire() }
        stopTimers()
    }

    private func fire() {
        guard hasNewChanges else {
            // Interval mode with nothing new: stop ticking until the next edit.
            intervalTimer?.invalidate()
            intervalTimer = nil
            return
        }
        hasNewChanges = false
        document?.takeSnapshot()
    }

    private func makeTimer(after interval: TimeInterval, repeats: Bool) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in self?.fire() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func stopTimers() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        intervalTimer?.invalidate()
        intervalTimer = nil
    }

    /// UserDefaults posts this for every change in the app (window sizes too), so only
    /// re-arm when the snapshot settings themselves changed.
    private func settingsMayHaveChanged() {
        let latest = SnapshotSettings.current
        guard latest != configuration else { return }
        configuration = latest
        stopTimers()
        if hasNewChanges { textDidChange() }
    }
}
