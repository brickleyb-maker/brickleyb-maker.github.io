import Photos
import SwiftUI

struct BinView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(DecisionStore.self) private var decisions

    @State private var assets: [PHAsset] = []
    @State private var totalBytes: Int64? = nil
    @State private var isDeleting = false
    @State private var errorMessage: String? = nil
    @State private var confirmRestore = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        ScrollView {
            if assets.isEmpty {
                ContentUnavailableView(
                    "Bin is empty",
                    systemImage: "trash",
                    description: Text("Swipe left on anything you want gone. It waits here until you delete it.")
                )
                .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap to put something back.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            Thumbnail(asset: asset)
                                .onTapGesture {
                                    withAnimation { decisions.restore(asset.localIdentifier) }
                                }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Bin")
        .toolbar {
            if !assets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore all") { confirmRestore = true }
                }
            }
        }
        .confirmationDialog("Put everything back?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore all \(assets.count)") { decisions.restoreAll() }
        }
        .safeAreaInset(edge: .bottom) {
            if !assets.isEmpty {
                VStack(spacing: 6) {
                    Button {
                        Task { await deleteAll() }
                    } label: {
                        HStack {
                            if isDeleting { ProgressView().tint(.white) }
                            Text(deleteTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(isDeleting)
                    Text("iOS will ask you to confirm. Items sit in Recently Deleted for 30 days; empty it in Photos to free the space now.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.bar)
            }
        }
        .alert("Couldn't delete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: decisions.binned) { await refresh() }
    }

    private var deleteTitle: String {
        let size = totalBytes.map { " · \(Format.bytes($0))" } ?? ""
        return "Delete \(assets.count) \(assets.count == 1 ? "item" : "items")\(size)"
    }

    private func refresh() async {
        let ids = decisions.binned
        let found = PhotoLibrary.fetch(ids: ids)
        if found.count != ids.count {
            decisions.pruneBin(keeping: Set(found.map(\.localIdentifier)))
        }
        assets = found
        totalBytes = nil
        let bytes = await SizeCache.shared.totalSize(of: found)
        if !Task.isCancelled { totalBytes = bytes }
    }

    private func deleteAll() async {
        let targets = assets
        guard !targets.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        let bytes = await SizeCache.shared.totalSize(of: targets)
        do {
            let done = try await library.delete(targets)
            guard done else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            decisions.markDeleted(targets.map(\.localIdentifier), bytes: bytes)
            await library.reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
