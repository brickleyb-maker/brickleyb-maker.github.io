import Photos
import SwiftUI

struct MonthsView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(DecisionStore.self) private var decisions
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatsCard(
                        total: library.snapshot.totalCount,
                        removedCount: decisions.removedCount,
                        removedBytes: decisions.removedBytes
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if library.status == .limited {
                    Section {
                        Label("Tidy can only see the photos you picked. Allow full access in Settings to review everything.", systemImage: "info.circle")
                            .font(.footnote)
                    }
                }

                ForEach(groupedByYear, id: \.year) { year in
                    Section(year.year) {
                        ForEach(year.months) { month in
                            NavigationLink {
                                SwipeDeckView(title: month.title, assets: month.assets)
                            } label: {
                                MonthRow(month: month, reviewed: reviewedCount(month))
                            }
                        }
                    }
                }
            }
            .overlay {
                if library.isLoading && !library.hasLoaded {
                    ProgressView("Reading your library…")
                } else if library.hasLoaded && library.snapshot.totalCount == 0 {
                    ContentUnavailableView("No photos", systemImage: "photo.on.rectangle", description: Text("Your library is empty."))
                }
            }
            .navigationTitle("Tidy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Start over on kept photos", systemImage: "arrow.counterclockwise") {
                            confirmReset = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Show photos you already kept again?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Start over") { decisions.resetKept() }
            } message: {
                Text("Your bin and deleted counts stay as they are.")
            }
            .refreshable { await library.reload() }
        }
    }

    private struct YearGroup {
        let year: String
        let months: [MonthBucket]
    }

    private var groupedByYear: [YearGroup] {
        var result: [YearGroup] = []
        for month in library.snapshot.months {
            let year = month.date == .distantPast ? "Undated" : String(Calendar.current.component(.year, from: month.date))
            if result.last?.year == year {
                result[result.count - 1] = YearGroup(year: year, months: result[result.count - 1].months + [month])
            } else {
                result.append(YearGroup(year: year, months: [month]))
            }
        }
        return result
    }

    private func reviewedCount(_ month: MonthBucket) -> Int {
        month.assets.reduce(0) { $0 + (decisions.isReviewed($1.localIdentifier) ? 1 : 0) }
    }
}

private struct MonthRow: View {
    let month: MonthBucket
    let reviewed: Int

    var body: some View {
        HStack(spacing: 12) {
            if let cover = month.assets.first {
                AssetImage(asset: cover, size: CGSize(width: 52, height: 52))
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(month.title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(reviewed), total: Double(max(month.assets.count, 1)))
                    .tint(reviewed >= month.assets.count ? .green : .accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let left = month.assets.count - reviewed
        return left == 0 ? "\(month.assets.count) items · done" : "\(month.assets.count) items · \(left) to review"
    }
}

private struct StatsCard: View {
    let total: Int
    let removedCount: Int
    let removedBytes: Int64

    var body: some View {
        HStack(spacing: 0) {
            stat(value: total.formatted(), label: "in library")
            Divider().frame(height: 36)
            stat(value: removedCount.formatted(), label: "removed")
            Divider().frame(height: 36)
            stat(value: Format.bytes(removedBytes), label: "cleared")
        }
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.teal.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding(.vertical, 4)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
