import Foundation
import Observation

/// Remembers what you kept and what is waiting in the bin.
/// Stored as a small JSON file inside the app's own sandbox. Never synced anywhere.
@MainActor
@Observable
final class DecisionStore {
    private(set) var kept: Set<String> = []
    /// Ordered so the bin shows most recent first.
    private(set) var binned: [String] = []
    private(set) var binnedSet: Set<String> = []
    private(set) var removedBytes: Int64 = 0
    private(set) var removedCount = 0

    private struct Snapshot: Codable {
        var kept: [String]
        var binned: [String]
        var removedBytes: Int64
        var removedCount: Int
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("decisions.json")
        load()
    }

    func isReviewed(_ id: String) -> Bool {
        kept.contains(id) || binnedSet.contains(id)
    }

    func keep(_ id: String) {
        unbinWithoutSaving(id)
        kept.insert(id)
        save()
    }

    func bin(_ id: String) {
        bin([id])
    }

    func bin(_ ids: [String]) {
        for id in ids where !binnedSet.contains(id) {
            kept.remove(id)
            binned.insert(id, at: 0)
            binnedSet.insert(id)
        }
        save()
    }

    func keep(_ ids: [String]) {
        for id in ids {
            unbinWithoutSaving(id)
            kept.insert(id)
        }
        save()
    }

    /// Forget any decision about this item (used by undo).
    func clear(_ id: String) {
        kept.remove(id)
        unbinWithoutSaving(id)
        save()
    }

    func restore(_ id: String) {
        unbinWithoutSaving(id)
        save()
    }

    func restoreAll() {
        binned = []
        binnedSet = []
        save()
    }

    func markDeleted(_ ids: [String], bytes: Int64) {
        for id in ids {
            unbinWithoutSaving(id)
            kept.remove(id)
        }
        removedBytes += bytes
        removedCount += ids.count
        save()
    }

    /// Drop bin entries for items that no longer exist (deleted in the Photos app, for example).
    func pruneBin(keeping existing: Set<String>) {
        let before = binned.count
        binned = binned.filter { existing.contains($0) }
        binnedSet = Set(binned)
        if binned.count != before { save() }
    }

    func resetKept() {
        kept = []
        save()
    }

    private func unbinWithoutSaving(_ id: String) {
        guard binnedSet.contains(id) else { return }
        binnedSet.remove(id)
        binned.removeAll { $0 == id }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        kept = Set(snap.kept)
        binned = snap.binned
        binnedSet = Set(snap.binned)
        removedBytes = snap.removedBytes
        removedCount = snap.removedCount
    }

    private func save() {
        let snap = Snapshot(kept: Array(kept), binned: binned, removedBytes: removedBytes, removedCount: removedCount)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
