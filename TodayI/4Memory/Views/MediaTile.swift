import SwiftUI

struct MediaTile: View {
  let source: MediaSource
  var cornerRadius: CGFloat = 12
  var minHeight: CGFloat = 160
  var onTap: (() -> Void)? = nil
  
  var body: some View {
    ZStack {
      switch source {
      case .local(let path):
        LocalImageView(path: path)
          .onAppear {
            print("Local image source \(path)")
          }
        
      case .remote(let url):
        // AsyncImage is fine for remote
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
}

private struct LocalImageView: View {
  let path: String
  
  var body: some View {
    Group {
      if FileManager.default.fileExists(atPath: path),
         let ui = UIImage(contentsOfFile: path) {
        // Direct path works
        Image(uiImage: ui)
          .resizable()
          .scaledToFill()
        
      } else if let ui = UIImage(contentsOfFile: URL(fileURLWithPath: path).path) {
        // Handles when you accidentally saved "file://..." string
        Image(uiImage: ui)
          .resizable()
          .scaledToFill()
        
      } else {
        // Debug fallback
        ZStack {
          Color.secondary.opacity(0.1)
          VStack {
            Image(systemName: "photo")
              .resizable()
              .scaledToFit()
              .padding(24)
              .foregroundStyle(.secondary)
          }
        }
        .onAppear {
          print("❌ LocalImageView failed for path:", path,
                "exists:", FileManager.default.fileExists(atPath: path))
        }
      }
    }
  }
}
