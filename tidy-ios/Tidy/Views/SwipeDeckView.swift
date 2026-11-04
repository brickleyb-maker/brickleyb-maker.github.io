import Photos
import SwiftUI

/// Tinder-style review: drag right to keep, left to bin. Undo walks back one card at a time.
struct SwipeDeckView: View {
    let title: String
    let assets: [PHAsset]

    @Environment(DecisionStore.self) private var decisions

    private enum Action { case keep, bin }

    @State private var queue: [PHAsset] = []
    @State private var prepared = false
    @State private var index = 0
    @State private var history: [Action] = []
    @State private var offset: CGSize = .zero
    @State private var preview: PreviewItem? = nil
    @State private var animating = false
    @State private var showBin = false
    @State private var binnedHere = 0

    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 16) {
            if !prepared {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if index >= queue.count {
                finished
            } else {
                header
                deck
                controls
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBin = true
                } label: {
                    Label("Bin \(decisions.binned.count)", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(decisions.binned.isEmpty)
            }
        }
        .sheet(isPresented: $showBin) {
            NavigationStack {
                BinView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showBin = false }
                        }
                    }
            }
        }
        .fullScreenCover(item: $preview) { item in
            PreviewView(asset: item.asset)
        }
        .onAppear(perform: prepare)
        .onChange(of: index) { _, _ in precache() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text("\(index + 1) of \(queue.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if binnedHere > 0 {
                Text("\(binnedHere) binned")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 8)
    }

    private var deck: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(visibleCards.reversed(), id: \.localIdentifier) { asset in
                    let isTop = asset.localIdentifier == queue[index].localIdentifier
                    SwipeCard(asset: asset, size: geo.size, offset: isTop ? offset : .zero, threshold: threshold)
                        .scaleEffect(isTop ? 1 : 0.95)
                        .offset(y: isTop ? 0 : 10)
                        .offset(isTop ? offset : .zero)
                        .rotationEffect(.degrees(isTop ? Double(offset.width / 22) : 0))
                        .allowsHitTesting(isTop)
                        .onTapGesture { preview = PreviewItem(asset: asset) }
                        .gesture(drag)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            CircleButton(systemImage: "trash.fill", tint: .red, size: 64) { fling(.bin) }
            CircleButton(systemImage: "arrow.uturn.backward", tint: .secondary, size: 48) { undo() }
                .disabled(history.isEmpty)
                .opacity(history.isEmpty ? 0.4 : 1)
            CircleButton(systemImage: "heart.fill", tint: .green, size: 64) { fling(.keep) }
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(queue.isEmpty ? "Nothing left to review here" : "All caught up")
                .font(.title2.bold())
            if !decisions.binned.isEmpty {
                Button {
                    showBin = true
                } label: {
                    Text("Review bin (\(decisions.binned.count))").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if !history.isEmpty {
                Button("Undo last") { undo() }
            }
            Spacer()
        }
    }

    private var visibleCards: [PHAsset] {
        Array(queue[index..<min(index + 2, queue.count)])
    }

    // MARK: Logic

    private var drag: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                if value.translation.width > threshold || predicted > threshold * 2.5 {
                    fling(.keep)
                } else if value.translation.width < -threshold || predicted < -threshold * 2.5 {
                    fling(.bin)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = .zero }
                }
            }
    }

    private func prepare() {
        guard !prepared else { return }
        queue = assets.filter { !decisions.isReviewed($0.localIdentifier) }
        prepared = true
        precache()
    }

    private func fling(_ action: Action) {
        guard index < queue.count, !animating else { return }
        animating = true
        UIImpactFeedbackGenerator(style: action == .bin ? .medium : .light).impactOccurred()
        let direction: CGFloat = action == .keep ? 1 : -1
        withAnimation(.easeIn(duration: 0.18)) {
            offset = CGSize(width: direction * 700, height: offset.height)
        } completion: {
            commit(action)
        }
    }

    private func commit(_ action: Action) {
        let id = queue[index].localIdentifier
        switch action {
        case .keep: decisions.keep(id)
        case .bin:
            decisions.bin(id)
            binnedHere += 1
        }
        history.append(action)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            offset = .zero
            index += 1
        }
        animating = false
    }

    private func undo() {
        guard !animating, index > 0, let last = history.popLast() else { return }
        index -= 1
        decisions.clear(queue[index].localIdentifier)
        if last == .bin { binnedHere = max(0, binnedHere - 1) }
    }

    private func precache() {
        let upcoming = Array(queue[min(index, queue.count)..<min(index + 5, queue.count)])
        guard !upcoming.isEmpty else { return }
        let side = UIScreen.main.bounds.width * UIScreen.main.scale
        ImageLoader.manager.startCachingImages(
            for: upcoming,
            targetSize: CGSize(width: side, height: side * 1.4),
            contentMode: .aspectFit,
            options: ImageLoader.options(highQuality: true)
        )
    }
}

private struct PreviewItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

private struct SwipeCard: View {
    let asset: PHAsset
    let size: CGSize
    let offset: CGSize
    let threshold: CGFloat

    @State private var bytes: Int64? = nil

    var body: some View {
        VStack(spacing: 0) {
            AssetImage(asset: asset, size: CGSize(width: size.width, height: size.height - 56), contentMode: .fit, highQuality: true)
                .frame(width: size.width, height: size.height - 56)
                .background(Color.black)
                .overlay {
                    if asset.mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    stamp("KEEP", color: .green)
                        .opacity(Double(max(0, offset.width) / threshold))
                        .rotationEffect(.degrees(-12))
                        .padding(24)
                }
                .overlay(alignment: .topTrailing) {
                    stamp("BIN", color: .red)
                        .opacity(Double(max(0, -offset.width) / threshold))
                        .rotationEffect(.degrees(12))
                        .padding(24)
                }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.date(asset.creationDate))
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if asset.isFavorite {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Color(.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .task(id: asset.localIdentifier) {
            let a = asset
            bytes = await Task.detached(priority: .utility) { SizeCache.shared.size(of: a) }.value
        }
    }

    private var detail: String {
        var parts: [String] = []
        if asset.mediaType == .video {
            parts.append("Video \(Format.duration(asset.duration))")
        } else if asset.mediaSubtypes.contains(.photoScreenshot) {
            parts.append("Screenshot")
        } else if asset.mediaSubtypes.contains(.photoLive) {
            parts.append("Live Photo")
        } else {
            parts.append("Photo")
        }
        if let bytes { parts.append(Format.bytes(bytes)) }
        return parts.joined(separator: " · ")
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
    }
}

struct CircleButton: View {
    let systemImage: String
    let tint: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(.secondarySystemBackground)))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}
