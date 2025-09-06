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
      
    case 2:
      HStack(spacing: 6) {
        ForEach(0..<2, id: \.self) { i in
          MediaTile(source: sources[i]) { onTap?(i) }
        }
      }
      .frame(height: 260)
      
    case 3:
      HStack(spacing: 6) {
        MediaTile(source: sources[0]) { onTap?(0) }
        VStack(spacing: 6) {
          MediaTile(source: sources[1]) { onTap?(1) }
          MediaTile(source: sources[2]) { onTap?(2) }
        }
      }
      .frame(height: 260)
      
    default:
      let firstNine = Array(sources.prefix(9))
      let over = sources.count - firstNine.count
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
        ForEach(firstNine.indices, id: \.self) { i in
          ZStack {
            MediaTile(source: firstNine[i]) { onTap?(i) }
            if i == firstNine.count - 1 && over > 0 {
              Color.black.opacity(0.35)
                .overlay(
                  Text("+\(over)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
          }
        }
      }
      .frame(height: 300)
    }
  }
}
