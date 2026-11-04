import Foundation
import Observation
import Photos
import UIKit

/// One calendar month of photos and videos, newest first.
struct MonthBucket: Identifiable, @unchecked Sendable {
    let id: String
    let date: Date
    var assets: [PHAsset]

    var title: String {
        if date == .distantPast { return "Undated" }
        return Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f
    }()
}

/// Everything Tidy needs from the library, built off the main thread in one pass.
struct LibrarySnapshot: @unchecked Sendable {
    var months: [MonthBucket] = []
    var screenshots: [PHAsset] = []
    var videos: [PHAsset] = []
    /// Still photos that are not screenshots, newest first. Used for the similar-photo scan.
    var photos: [PHAsset] = []
    var totalCount = 0
}

/// Read and delete access to the on-device photo library. No networking anywhere in this app.
@MainActor
@Observable
final class PhotoLibrary {
    private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var snapshot = LibrarySnapshot()
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    var isAuthorized: Bool { status == .authorized || status == .limited }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await reload()
    }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func reload() async {
        refreshStatus()
        guard isAuthorized, !isLoading else { return }
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) {
            PhotoLibrary.buildSnapshot()
        }.value
        snapshot = result
        isLoading = false
        hasLoaded = true
    }

    /// Deletes assets. iOS shows its own confirmation, and items go to Recently Deleted for 30 days.
    /// Returns false if the person cancelled the system prompt.
    func delete(_ assets: [PHAsset]) async throws -> Bool {
        guard !assets.isEmpty else { return true }
        let array = assets as NSArray
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(array)
            }
            return true
        } catch {
            if let photosError = error as? PHPhotosError, photosError.code == .userCancelled {
                return false
            }
            throw error
        }
    }

    nonisolated static func buildSnapshot() -> LibrarySnapshot {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Only your own library. Shared albums and synced items can't be deleted from an app.
        options.includeAssetSourceTypes = [.typeUserLibrary]
        let all = PHAsset.fetchAssets(with: options)

        var snap = LibrarySnapshot()
        let calendar = Calendar.current
        var current: MonthBucket?

        for index in 0..<all.count {
            let asset = all.object(at: index)
            guard asset.mediaType == .image || asset.mediaType == .video else { continue }
            snap.totalCount += 1

            let key: String
            let monthDate: Date
            if let created = asset.creationDate {
                let comps = calendar.dateComponents([.year, .month], from: created)
                key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
                monthDate = calendar.date(from: comps) ?? created
            } else {
                key = "undated"
                monthDate = .distantPast
            }

            if current?.id != key {
                if let finished = current { snap.months.append(finished) }
                current = MonthBucket(id: key, date: monthDate, assets: [])
            }
            current?.assets.append(asset)

            if asset.mediaType == .video {
                snap.videos.append(asset)
            } else if asset.mediaSubtypes.contains(.photoScreenshot) {
                snap.screenshots.append(asset)
            } else {
                snap.photos.append(asset)
            }
        }
        if let finished = current { snap.months.append(finished) }
        return snap
    }

    static func fetch(ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: PHAsset] = [:]
        for i in 0..<result.count {
            let asset = result.object(at: i)
            byID[asset.localIdentifier] = asset
        }
        return ids.compactMap { byID[$0] }
    }
}

/// On-device file sizes, cached. Reads metadata only.
final class SizeCache: @unchecked Sendable {
    static let shared = SizeCache()
    private var cache: [String: Int64] = [:]
    private let lock = NSLock()

    func size(of asset: PHAsset) -> Int64 {
        let id = asset.localIdentifier
        lock.lock()
        if let hit = cache[id] { lock.unlock(); return hit }
        lock.unlock()

        var total: Int64 = 0
        for resource in PHAssetResource.assetResources(for: asset) {
            if let bytes = resource.value(forKey: "fileSize") as? Int64 {
                total += bytes
            } else if let bytes = resource.value(forKey: "fileSize") as? Int {
                total += Int64(bytes)
            }
        }

        lock.lock()
        cache[id] = total
        lock.unlock()
        return total
    }

    func totalSize(of assets: [PHAsset]) async -> Int64 {
        await Task.detached(priority: .utility) {
            assets.reduce(Int64(0)) { $0 + self.size(of: $1) }
        }.value
    }
}

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "Undated" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
