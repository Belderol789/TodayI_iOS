import SwiftUI
import AVKit

struct MediaTile: View {
  let source: MediaSource
  var cornerRadius: CGFloat = 12
  var minHeight: CGFloat = 160
  var onTap: (() -> Void)? = nil
  
  var body: some View {
    ZStack {
      switch source {
      case .localImage(let path):
        LocalImageView(path: path)
          .onAppear { print("📷 Local image source \(path)") }
        
      case .remoteImage(let url):
        AsyncImage(url: url) { phase in
          switch phase {
          case .empty:
            ProgressView()
          case .success(let img):
            img.resizable().scaledToFill()
          case .failure:
            placeholder
          @unknown default:
            placeholder
          }
        }
        
      case .localVideo(let path):
        if FileManager.default.fileExists(atPath: path) {
          VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: path)))
            .onAppear { print("🎥 Local video source \(path)") }
        } else {
          placeholderVideo
        }
        
      case .remoteVideo(let url):
        VideoPlayer(player: AVPlayer(url: url))
          .onAppear { print("🌐 Remote video source \(url)") }
      }
    }
    .frame(maxWidth: .infinity, minHeight: minHeight)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .onTapGesture { onTap?() }
  }
  
  private var placeholder: some View {
    Image(systemName: "photo")
      .resizable()
      .scaledToFit()
      .padding(24)
      .foregroundStyle(.secondary)
  }
  
  private var placeholderVideo: some View {
    ZStack {
      Color.secondary.opacity(0.1)
      Image(systemName: "video")
        .resizable()
        .scaledToFit()
        .padding(24)
        .foregroundStyle(.secondary)
    }
  }
}
