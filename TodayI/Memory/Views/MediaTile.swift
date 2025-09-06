import SwiftUI

struct MediaTile: View {
  let source: MediaSource
  var cornerRadius: CGFloat = 12
  var minHeight: CGFloat? = nil      // set for “hero” usage
  var onTap: (() -> Void)? = nil
  
  @Environment(\.colorScheme) private var scheme
  
  var body: some View {
    content
      .background(placeholder)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .onTapGesture { onTap?() }
  }
  
  @ViewBuilder
  private var content: some View {
    switch source {
    case .symbol(let name):
      ZStack {
        placeholder
        Image(systemName: name)
          .resizable()
          .scaledToFit()
          .padding(22)
          .foregroundStyle(.secondary)
      }
      .aspectRatio(1, contentMode: .fit)
      .frame(minHeight: minHeight)
      
    case .local(let path):
      if let ui = UIImage(contentsOfFile: path) {
        Image(uiImage: ui)
          .resizable()
          .scaledToFill()
          .aspectRatio(1, contentMode: .fit)
          .frame(minHeight: minHeight)
      } else {
        placeholder.aspectRatio(1, contentMode: .fit).frame(minHeight: minHeight)
      }
      
    case .remote(let url):
      AsyncImage(url: url) { phase in
        switch phase {
        case .empty:
          placeholder.aspectRatio(1, contentMode: .fit).frame(minHeight: minHeight)
        case .success(let img):
          img.resizable().scaledToFill()
            .aspectRatio(1, contentMode: .fit)
            .frame(minHeight: minHeight)
        case .failure:
          ZStack {
            placeholder
            Image(systemName: "wifi.exclamationmark")
              .imageScale(.large)
              .foregroundStyle(.secondary)
          }
          .aspectRatio(1, contentMode: .fit)
          .frame(minHeight: minHeight)
        @unknown default:
          placeholder.aspectRatio(1, contentMode: .fit).frame(minHeight: minHeight)
        }
      }
    }
  }
  
  private var placeholder: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
  }
}
