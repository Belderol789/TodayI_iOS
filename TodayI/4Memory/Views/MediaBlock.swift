import SwiftUI

struct MediaBlock: View {
  let sources: [MediaSource]
  var onTap: ((Int) -> Void)? = nil
  
  // centralize sizes so everything is consistent
  private let heroMinH: CGFloat = 220
  private let heroMaxH: CGFloat = 320
  private let galleryTileSize = CGSize(width: 220, height: 180)
  private let galleryHeight: CGFloat = 190
  
  var body: some View {
    switch sources.count {
    case 0:
      EmptyView()
      
    case 1:
      // SINGLE “HERO” — the wrapper owns sizing + clipping
      ZStack {
        MediaTile(source: sources[0], cornerRadius: 0, minHeight: heroMinH) { onTap?(0) }
      }
      .frame(maxWidth: .infinity,
             minHeight: heroMinH,
             maxHeight: heroMaxH,
             alignment: .center)
      .clipped() // <- ensures scaledToFill never overflows
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      
    default:
      // GALLERY — align with content width, no extra insets
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(sources.indices, id: \.self) { i in
            MediaTile(source: sources[i], cornerRadius: 12, minHeight: galleryTileSize.height) {
              onTap?(i)
            }
            .frame(width: galleryTileSize.width, height: galleryTileSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
        .padding(.horizontal, 0) // keep edges aligned with text/link
      }
      .frame(maxWidth: .infinity,
             minHeight: galleryHeight,
             maxHeight: galleryHeight,
             alignment: .leading)
    }
  }
}
