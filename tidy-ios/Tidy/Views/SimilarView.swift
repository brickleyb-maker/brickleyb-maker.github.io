import Photos
import SwiftUI

struct SimilarView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(DecisionStore.self) private var decisions
    @Environment(SimilarScanner.self) private var scanner
    @State private var scope: SimilarScanner.Scope = .quarter
    @State private var preview: SizedAsset? = nil

    var body: some View {
        @Bindable var scanner = scanner
        List {
            Section {
                Picker("Look at", selection: $scope) {
                    ForEach(SimilarScanner.Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                if scanner.isScanning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: scanner.progress)
                        HStack {
                            Text("Scanned \(scanner.processed.formatted()) of \(scanner.total.formatted())")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Stop") { scanner.cancel() }
                                .font(.caption.bold())
                        }
                    }
                } else {
                    Button {
                        scanner.start(photos: library.snapshot.photos, scope: scope, excluding: decisions.binnedSet)
                    } label: {
                        Label(scanner.hasResults ? "Scan again" : "Find similar photos", systemImage: "sparkle.magnifyingglass")
                    }
                }
            } footer: {
                Text("Runs entirely on this phone using Apple's Vision framework. Scanning thousands of photos takes a few minutes.")
            }

            if scanner.hasResults {
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Strict")
                            Slider(value: $scanner.threshold, in: 0.2...0.9)
                            Text("Loose")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("\(scanner.groups.count) groups found")
                } footer: {
                    Text("Tidy pre-selects everything except the sharpest, largest shot in each group. Tap a photo to flip it.")
                }

                ForEach(scanner.groups) { group in
                    Section {
                        GroupRow(group: group) { preview = SizedAsset(asset: $0, bytes: 0) }
                    } header: {
                        HStack {
                            Text(Format.date(group.assets.first?.creationDate))
                            Spacer()
                            Button("Not similar") { scanner.dismiss(group) }
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle("Similar photos")
        .safeAreaInset(edge: .bottom) {
            if scanner.hasResults && scanner.markedCount > 0 {
                Button {
                    let result = scanner.resolveAll()
                    decisions.keep(result.keep)
                    decisions.bin(result.bin)
                } label: {
                    Text("Move \(scanner.markedCount) to bin").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        .fullScreenCover(item: $preview) { item in
            PreviewView(asset: item.asset)
        }
    }
}

private struct GroupRow: View {
    let group: SimilarGroup
    let onLongPress: (PHAsset) -> Void
    @Environment(SimilarScanner.self) private var scanner

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(group.assets, id: \.localIdentifier) { asset in
                    let marked = scanner.isMarked(asset, in: group)
                    Thumbnail(asset: asset, dimmed: marked, badge: marked ? "xmark.circle.fill" : nil)
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            if asset.localIdentifier == group.bestID {
                                Image(systemName: "star.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .yellow)
                                    .font(.title3)
                                    .padding(4)
                            }
                        }
                        .onTapGesture { scanner.toggle(asset, in: group) }
                        .onLongPressGesture { onLongPress(asset) }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}
