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
      case .localImage(let path):
        normalizedImage(
          FileImage(path: path, contentMode: .fill) // ✅ fill, no fixed frame
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
                .scaledToFill() // ✅ fill container
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

      case .localAudio(let path):
        normalizedAudio(source: .localAudio(path: path))

      case .remoteAudio(let url):
        normalizedAudio(source: .remoteAudio(url: url))
      }
    }
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
  
  // MARK: - Normalizers
  
  /// Ensures image-like content fills width, has consistent height, and clips.
  private func normalizedImage<Content: View>(_ content: Content) -> some View {
    ZStack { content }                       // content must be resizable (it is)
      .frame(maxWidth: .infinity)            // fill horizontally
      .frame(minHeight: minHeight)           // consistent height
      .clipped()                             // crop overflow (for .fill)
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .onTapGesture { onTap?() }
  }
  
  /// Renders an audio player with the same footprint as other media tiles.
  private func normalizedAudio(source: MediaSource) -> some View {
    AudioPlayerRow(source: source, moodColor: .accentColor)
      .frame(maxWidth: .infinity)
      .frame(minHeight: minHeight)
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .onTapGesture { onTap?() }
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

// MARK: - Local file image loader
private struct FileImage: View {
  let path: String
  var contentMode: ContentMode = .fill
  
  var body: some View {
    if let ui = UIImage(contentsOfFile: path) {
      Image(uiImage: ui)
        .resizable()
        .aspectRatio(contentMode: contentMode) // .fill by default
    } else {
      Color.secondary.opacity(0.1) // fallback
    }
  }
}
