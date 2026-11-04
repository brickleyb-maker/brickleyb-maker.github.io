import AVKit
import Photos
import SwiftUI

/// Full-screen look at one item. Videos play inline.
struct PreviewView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if asset.mediaType == .video {
                    if let player {
                        VideoPlayer(player: player)
                    } else {
                        ProgressView().tint(.white)
                    }
                } else {
                    AssetImage(asset: asset, size: geo.size, contentMode: .fit, highQuality: true)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            Text(Format.date(asset.creationDate))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, asset.mediaType == .video ? 80 : 24)
        }
        .task { await loadVideo() }
        .onDisappear { player?.pause() }
    }

    private func loadVideo() async {
        guard asset.mediaType == .video else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
        guard let item else { return }
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        newPlayer.play()
    }
}
