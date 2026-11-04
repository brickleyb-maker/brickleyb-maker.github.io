import Photos
import SwiftUI

struct CleanupView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(DecisionStore.self) private var decisions

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SimilarView()
                    } label: {
                        row("Similar photos", detail: "Bursts, near-duplicates, retakes", icon: "square.on.square", tint: .purple)
                    }
                    NavigationLink {
                        LargeVideosView()
                    } label: {
                        row("Large videos", detail: "\(library.snapshot.videos.count) videos, biggest first", icon: "film", tint: .orange)
                    }
                    NavigationLink {
                        SwipeDeckView(title: "Screenshots", assets: library.snapshot.screenshots)
                    } label: {
                        row("Screenshots", detail: "\(unreviewed(library.snapshot.screenshots)) to review", icon: "camera.viewfinder", tint: .blue)
                    }
                } footer: {
                    Text("Exact duplicates are also listed in Apple's Photos app under Utilities > Duplicates.")
                }
            }
            .navigationTitle("Clean Up")
        }
    }

    private func unreviewed(_ assets: [PHAsset]) -> Int {
        assets.reduce(0) { $0 + (decisions.isReviewed($1.localIdentifier) ? 0 : 1) }
    }

    private func row(_ title: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SizedAsset: Identifiable, @unchecked Sendable {
    let asset: PHAsset
    let bytes: Int64
    var id: String { asset.localIdentifier }
}

struct LargeVideosView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(DecisionStore.self) private var decisions
    @State private var items: [SizedAsset]? = nil
    @State private var preview: SizedAsset? = nil

    var body: some View {
        Group {
            if let items {
                List {
                    Section {
                        NavigationLink {
                            SwipeDeckView(title: "Large videos", assets: items.map(\.asset))
                        } label: {
                            Label("Swipe through, biggest first", systemImage: "hand.draw")
                        }
                    } footer: {
                        Text("\(items.count) videos · \(Format.bytes(items.reduce(Int64(0)) { $0 + $1.bytes })) total")
                    }

                    Section("Biggest") {
                        ForEach(items.prefix(150)) { item in
                            HStack(spacing: 12) {
                                Button {
                                    preview = item
                                } label: {
                                    Thumbnail(asset: item.asset)
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Format.bytes(item.bytes)).font(.headline)
                                    Text("\(Format.duration(item.asset.duration)) · \(Format.date(item.asset.creationDate))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                binToggle(item.asset)
                            }
                        }
                    }
                }
            } else {
                ProgressView("Measuring videos…")
            }
        }
        .navigationTitle("Large videos")
        .fullScreenCover(item: $preview) { item in
            PreviewView(asset: item.asset)
        }
        .task {
            guard items == nil else { return }
            let videos = library.snapshot.videos
            items = await Task.detached(priority: .userInitiated) {
                videos
                    .map { SizedAsset(asset: $0, bytes: SizeCache.shared.size(of: $0)) }
                    .sorted { $0.bytes > $1.bytes }
            }.value
        }
    }

    private func binToggle(_ asset: PHAsset) -> some View {
        let inBin = decisions.binnedSet.contains(asset.localIdentifier)
        return Button {
            if inBin { decisions.restore(asset.localIdentifier) } else { decisions.bin(asset.localIdentifier) }
        } label: {
            Image(systemName: inBin ? "trash.fill" : "trash")
                .font(.title3)
                .foregroundStyle(inBin ? .red : .secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}
