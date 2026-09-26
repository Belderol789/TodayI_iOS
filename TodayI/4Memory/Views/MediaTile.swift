import SwiftUI
import AVKit
import AVFoundation

struct MediaTile: View {
  let source: MediaSource
  var cornerRadius: CGFloat = 12
  var minHeight: CGFloat = 160
  var accentColor: Color = .accentColor
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

      // Personal entries: no token, so the file comes through the authenticated SDK.
      // Resolves to a cached local file and then renders exactly like local media.
      case .protectedImage(let path):
        ProtectedMedia(path: path) { local in
          normalizedImage(FileImage(path: local.path, contentMode: .fill))
        }

      case .protectedVideo(let path):
        ProtectedMedia(path: path) { local in
          normalizedVideo(url: local)
        }

      case .protectedAudio(let path):
        ProtectedMedia(path: path) { local in
          normalizedAudio(source: .localAudio(path: local.path))
        }
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
    AudioPlayerRow(source: source, moodColor: accentColor)
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


// MARK: - Protected media loader

/// Resolves a storage path to a cached local file, then hands it to `content`.
///
/// Only reached for Personal entries whose local copy is missing — a reinstall or a
/// second device — so the spinner is rare by construction.
struct ProtectedMedia<Content: View>: View {
  let path: String
  @ViewBuilder var content: (URL) -> Content

  @State private var localURL: URL?
  @State private var failed = false

  var body: some View {
    Group {
      if let localURL {
        content(localURL)
      } else if failed {
        Image(systemName: "lock.slash")
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 160)
          .accessibilityLabel("This media could not be loaded")
      } else {
        ZStack {
          Color.clear
          ProgressView()
        }
        .frame(maxWidth: .infinity, minHeight: 160)
      }
    }
    .task(id: path) {
      guard localURL == nil else { return }
      if let url = await ProtectedMediaStore.shared.localURL(forPath: path) {
        localURL = url
      } else {
        failed = true
      }
    }
  }
}
