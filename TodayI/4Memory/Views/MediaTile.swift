import SwiftUI
import AVKit
import AVFoundation

struct MediaTile: View {
  let source: MediaSource
  var cornerRadius: CGFloat = 12
  var minHeight: CGFloat = 160
  var onTap: (() -> Void)? = nil
  
  var body: some View {
    Group {
      switch source {
        // Inside MediaTile
      case .localImage(let path):
        normalizedImage(
          Image(path)                   // or LocalImageView(path: path)
            .resizable()                // force resizable
            .scaledToFill()             // fill the frame
        )
        
      case .remoteImage(let url):
        normalizedImage(
          AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
              ZStack {
                Color.clear
                ProgressView()
              }
            case .success(let img):
              img
                .resizable()
                .scaledToFill()     // ✅ ensures remote doesn’t expand to natural size
            case .failure:
              placeholder
            @unknown default:
              placeholder
            }
          }
        )
        
      case .localVideo(let path):
        normalizedVideo(url: URL(fileURLWithPath: path))
        
      case .remoteVideo(let url):
        normalizedVideo(url: url)
      }
    }
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
  
  // MARK: - Normalizers
  
  /// Ensures any image-like content fills width, has consistent height, and clips.
  private func normalizedImage<Content: View>(_ content: Content) -> some View {
    ZStack {
      content
    }
    .frame(maxWidth: .infinity)       // fill horizontally
    .frame(minHeight: minHeight,
           maxHeight: 320)            // keep a sane vertical bound
    .clipped()                        // prevent overflow
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .onTapGesture { onTap?() }
  }
  
  /// Ensures videos get the same footprint as images.
  private func normalizedVideo(url: URL) -> some View {
    InteractablePlayOverlayPlayer(
      url: url,
      cornerRadius: cornerRadius,
      minHeight: minHeight
    )
    .frame(maxWidth: .infinity)
    .frame(minHeight: minHeight)
  }
  
  private var placeholder: some View {
    ZStack {
      Color.clear
      Image(systemName: "photo")
        .resizable()
        .scaledToFit()
        .padding(24)
        .foregroundStyle(.secondary)
    }
  }
}
