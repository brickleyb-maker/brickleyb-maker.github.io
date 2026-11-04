import Photos
import SwiftUI

enum ImageLoader {
    static let manager = PHCachingImageManager()

    static func options(highQuality: Bool) -> PHImageRequestOptions {
        let o = PHImageRequestOptions()
        o.deliveryMode = highQuality ? .opportunistic : .fastFormat
        o.resizeMode = highQuality ? .exact : .fast
        // Lets Apple's Photos system pull a full-size copy of your own iCloud photo when needed.
        // Tidy itself makes no network calls.
        o.isNetworkAccessAllowed = highQuality
        return o
    }
}

/// Loads a photo or video frame from the library at a given point size.
struct AssetImage: View {
    let asset: PHAsset
    var size: CGSize
    var contentMode: ContentMode = .fill
    var highQuality = false

    @Environment(\.displayScale) private var scale
    @State private var image: UIImage? = nil
    @State private var requestID: PHImageRequestID? = nil

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color(.secondarySystemBackground))
                ProgressView()
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: cancel)
        .onChange(of: asset.localIdentifier) { _, _ in
            cancel()
            image = nil
            load()
        }
    }

    private func load() {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        requestID = ImageLoader.manager.requestImage(
            for: asset,
            targetSize: pixels,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit,
            options: ImageLoader.options(highQuality: highQuality)
        ) { result, _ in
            if let result { image = result }
        }
    }

    private func cancel() {
        if let requestID { ImageLoader.manager.cancelImageRequest(requestID) }
        requestID = nil
    }
}

/// Square grid thumbnail with video and selection badges.
struct Thumbnail: View {
    let asset: PHAsset
    var dimmed = false
    var badge: String? = nil

    var body: some View {
        GeometryReader { geo in
            AssetImage(asset: asset, size: geo.size)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if asset.mediaType == .video {
                        Text(Format.duration(asset.duration))
                            .font(.caption2.bold())
                            .padding(4)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                .overlay {
                    if dimmed { Color.black.opacity(0.45) }
                }
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Image(systemName: badge)
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .padding(4)
                    }
                }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
