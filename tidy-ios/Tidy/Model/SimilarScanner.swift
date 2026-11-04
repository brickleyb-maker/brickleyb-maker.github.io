import Foundation
import Observation
import Photos
import UIKit
import Vision

struct SimilarGroup: Identifiable {
    let id: String
    let assets: [PHAsset]
    /// The photo Tidy suggests keeping: highest resolution, then favorites, then newest.
    let bestID: String
}

/// Finds near-duplicate and burst-style similar photos using Apple's on-device Vision feature prints.
/// Each photo is compared with its neighbors in time, so the work grows linearly with library size.
@MainActor
@Observable
final class SimilarScanner {
    enum Scope: String, CaseIterable, Identifiable {
        case month = "Last 30 days"
        case quarter = "Last 3 months"
        case year = "Last 12 months"
        case everything = "Everything"

        var id: String { rawValue }

        var cutoff: Date? {
            let cal = Calendar.current
            switch self {
            case .month: return cal.date(byAdding: .day, value: -30, to: .now)
            case .quarter: return cal.date(byAdding: .month, value: -3, to: .now)
            case .year: return cal.date(byAdding: .year, value: -1, to: .now)
            case .everything: return nil
            }
        }
    }

    private struct Edge {
        let a: Int
        let b: Int
        let distance: Float
    }

    /// How many neighbors (by capture time) each photo is compared against.
    private static let window = 6

    private(set) var isScanning = false
    private(set) var processed = 0
    private(set) var total = 0
    private(set) var hasResults = false
    private(set) var groups: [SimilarGroup] = []

    /// Lower is stricter. Vision feature print distances (revision 2) run roughly 0 to 2.
    var threshold: Float = 0.45 {
        didSet { regroup() }
    }

    /// Items the person toggled by hand. Missing means "use the suggestion".
    private var overrides: [String: Bool] = [:]
    private var dismissedGroups: Set<String> = []
    private var scanned: [PHAsset] = []
    private var edges: [Edge] = []
    private var task: Task<Void, Never>?
    private var generation = 0

    var progress: Double { total == 0 ? 0 : Double(processed) / Double(total) }

    func start(photos: [PHAsset], scope: Scope, excluding excluded: Set<String>) {
        cancel()
        let cutoff = scope.cutoff
        let list = photos.filter { asset in
            if excluded.contains(asset.localIdentifier) { return false }
            guard let cutoff else { return true }
            return (asset.creationDate ?? .distantPast) >= cutoff
        }

        scanned = list
        edges = []
        groups = []
        overrides = [:]
        dismissedGroups = []
        processed = 0
        total = list.count
        hasResults = false
        isScanning = true
        generation += 1
        let gen = generation

        let window = Self.window
        task = Task.detached(priority: .userInitiated) { [weak self] in
            var prints: [VNFeaturePrintObservation?] = []
            prints.reserveCapacity(list.count)
            var found: [Edge] = []

            for (index, asset) in list.enumerated() {
                if Task.isCancelled { break }
                let current = autoreleasepool { SimilarScanner.featurePrint(for: asset) }
                prints.append(current)

                if let current {
                    for other in max(0, index - window)..<index {
                        guard let otherPrint = prints[other] else { continue }
                        var distance: Float = 0
                        if (try? current.computeDistance(&distance, to: otherPrint)) != nil {
                            found.append(Edge(a: other, b: index, distance: distance))
                        }
                    }
                }

                if index % 20 == 19 {
                    let done = index + 1
                    await MainActor.run {
                        guard let self, self.generation == gen else { return }
                        self.processed = done
                    }
                }
            }

            let finalEdges = found
            let done = prints.count
            await MainActor.run {
                guard let self, self.generation == gen else { return }
                self.processed = done
                self.edges = finalEdges
                self.isScanning = false
                self.hasResults = true
                self.regroup()
            }
        }
    }

    /// Stops the scan early. Results so far are kept when the scan winds down.
    func cancel() {
        task?.cancel()
        task = nil
    }

    func isMarked(_ asset: PHAsset, in group: SimilarGroup) -> Bool {
        overrides[asset.localIdentifier] ?? (asset.localIdentifier != group.bestID)
    }

    func toggle(_ asset: PHAsset, in group: SimilarGroup) {
        overrides[asset.localIdentifier] = !isMarked(asset, in: group)
    }

    func dismiss(_ group: SimilarGroup) {
        dismissedGroups.insert(group.id)
        groups.removeAll { $0.id == group.id }
    }

    var markedCount: Int {
        groups.reduce(0) { count, group in
            count + group.assets.filter { isMarked($0, in: group) }.count
        }
    }

    /// Returns (to bin, to keep) and clears those groups from the list.
    func resolveAll() -> (bin: [String], keep: [String]) {
        var toBin: [String] = []
        var toKeep: [String] = []
        for group in groups {
            for asset in group.assets {
                if isMarked(asset, in: group) {
                    toBin.append(asset.localIdentifier)
                } else {
                    toKeep.append(asset.localIdentifier)
                }
            }
            dismissedGroups.insert(group.id)
        }
        groups = []
        return (toBin, toKeep)
    }

    private func regroup() {
        guard hasResults else { return }
        var parent = Array(0..<scanned.count)

        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        for edge in edges where edge.distance <= threshold {
            let ra = find(edge.a), rb = find(edge.b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }

        var members: [Int: [Int]] = [:]
        for i in 0..<scanned.count {
            members[find(i), default: []].append(i)
        }

        groups = members
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .compactMap { _, indices in
                let assets = indices.map { scanned[$0] }
                let id = assets[0].localIdentifier
                guard !dismissedGroups.contains(id) else { return nil }
                let best = assets.max { lhs, rhs in
                    let l = (lhs.pixelWidth * lhs.pixelHeight, lhs.isFavorite ? 1 : 0, lhs.creationDate ?? .distantPast)
                    let r = (rhs.pixelWidth * rhs.pixelHeight, rhs.isFavorite ? 1 : 0, rhs.creationDate ?? .distantPast)
                    return l < r
                }
                return SimilarGroup(id: id, assets: assets, bestID: best?.localIdentifier ?? id)
            }
    }

    nonisolated static func featurePrint(for asset: PHAsset) -> VNFeaturePrintObservation? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        var cgImage: CGImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 360, height: 360),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            cgImage = image?.cgImage
        }
        guard let cgImage else { return nil }

        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first
    }
}
