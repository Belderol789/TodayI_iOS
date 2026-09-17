import SwiftUI

/// Full-bleed photo block for a memory card, shaped like Instagram/Facebook:
/// the image spans the card's whole width and is sized by aspect ratio rather than a
/// fixed pixel height, so it reads as a large photo instead of a thumbnail.
/// Multiple images become a swipeable pager with a counter and dots, not a strip of tiles.
struct MediaBlock: View {
  let sources: [MediaSource]
  var onTap: ((Int) -> Void)? = nil

  /// width ÷ height. 4:5 is Instagram's tallest portrait crop — the most generous
  /// shape that still leaves the caption and actions visible without scrolling.
  var aspect: CGFloat = 4.0 / 5.0

  /// 0 keeps the photo flush with the card edges; the card itself does the rounding.
  var cornerRadius: CGFloat = 0

  @State private var index: Int = 0

  var body: some View {
    switch sources.count {
    case 0:
      EmptyView()
    case 1:
      photoBox {
        MediaTile(source: sources[0], cornerRadius: cornerRadius, minHeight: 0) {
          onTap?(0)
        }
      }
    default:
      pager
    }
  }

  // MARK: - Pager

  private var pager: some View {
    photoBox {
      TabView(selection: $index) {
        ForEach(sources.indices, id: \.self) { i in
          MediaTile(source: sources[i], cornerRadius: cornerRadius, minHeight: 0) {
            onTap?(i)
          }
          .tag(i)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
    }
    .overlay(alignment: .topTrailing) { counter }
    .overlay(alignment: .bottom) { dots }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Photo \(index + 1) of \(sources.count)")
    .accessibilityHint("Swipe left or right to see the other photos.")
  }

  private var counter: some View {
    Text("\(index + 1)/\(sources.count)")
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.black.opacity(0.55), in: Capsule())
      .padding(12)
      .accessibilityHidden(true)
  }

  private var dots: some View {
    HStack(spacing: 6) {
      ForEach(sources.indices, id: \.self) { i in
        Circle()
          .fill(.white.opacity(i == index ? 0.95 : 0.45))
          .frame(width: 6, height: 6)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.black.opacity(0.28), in: Capsule())
    .padding(.bottom, 12)
    .animation(.easeInOut(duration: 0.15), value: index)
    .accessibilityHidden(true)
  }

  // MARK: - Layout

  /// A box that takes the full available width and derives its height from `aspect`,
  /// so the photo scales with the device instead of being pinned to a fixed height.
  private func photoBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    Color.clear
      .aspectRatio(aspect, contentMode: .fit)
      .overlay { content() }
      .clipped()
  }
}
