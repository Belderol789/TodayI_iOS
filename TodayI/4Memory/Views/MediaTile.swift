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
        imageBody(LocalImageView(path: path))
        
      case .remoteImage(let url):
        imageBody(
          AsyncImage(url: url) { phase in
            switch phase {
            case .empty: ProgressView()
            case .success(let img): img.resizable().scaledToFill()
            case .failure: placeholder
            @unknown default: placeholder
            }
          }
        )
        
      case .localVideo(let path):
        videoBody(url: URL(fileURLWithPath: path))
        
      case .remoteVideo(let url):
        videoBody(url: url)
      }
    }
    .frame(maxWidth: .infinity, minHeight: minHeight)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
  
  // MARK: - Builders
  
  private func imageBody<Content: View>(_ content: Content) -> some View {
    content
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .onTapGesture { onTap?() }
  }
  
  private func videoBody(url: URL) -> some View {
    InteractablePlayOverlayPlayer(
      url: url,
      cornerRadius: cornerRadius,
      minHeight: minHeight
    )
  }
  
  private var placeholder: some View {
    Image(systemName: "photo")
      .resizable()
      .scaledToFit()
      .padding(24)
      .foregroundStyle(.secondary)
  }
}
