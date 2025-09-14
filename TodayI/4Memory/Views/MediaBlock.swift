import SwiftUI

struct MediaBlock: View {
  let sources: [MediaSource]
  var onTap: ((Int) -> Void)? = nil
  
  var body: some View {
    switch sources.count {
    case 0:
      EmptyView()
      
    case 1:
      // Hero tile
      MediaTile(source: sources[0], cornerRadius: 14, minHeight: 220) {
        onTap?(0)
      }
      .frame(maxWidth: .infinity, maxHeight: 320)
      
    default:
      // Horizontally scrollable gallery for 2+
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(sources.indices, id: \.self) { i in
            MediaTile(source: sources[i], cornerRadius: 12, minHeight: 160) {
              onTap?(i)
            }
            .frame(width: 220, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
        .padding(.horizontal, 2)
      }
      .frame(height: 190)
    }
  }
}
