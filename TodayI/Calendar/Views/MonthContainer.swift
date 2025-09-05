import SwiftUI

enum MonthChrome {
  case none
  case card
  case tinted([Color], strength: Double = 1)   // one or many colors
}

enum PageEdge { case rounded, fullBleed }

// Use this wrapper around a month so it can morph (zoom) between Pager <-> YearGrid
struct MonthContainer<Content: View>: View {
  let month: Date
  let id: AnyHashable
  let zoomNS: Namespace.ID
  let isMatched: Bool
  let isSource: Bool
  let chrome: MonthChrome
  let pageEdge: PageEdge              // <—
  @ViewBuilder var content: Content
  @Environment(\.colorScheme) private var scheme
  @Environment(\.calendarInsets) private var calendarInsets
  
  var body: some View {
    ZStack {
      backgroundShape
        .fill(fillStyle)
        .overlay(borderOverlay)
        .shadow(color: shadowColor, radius: shadowRadius, y: 2)
        .modifier(MatchedIfNeeded(id: id, ns: zoomNS, isMatched: isMatched, isSource: isSource))
      
      content
        .padding(.horizontal, pageEdge == .fullBleed ? calendarInsets.leading : 0)
        .padding(.vertical,   pageEdge == .fullBleed ? calendarInsets.top    : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .clipped()
  }
  
  // MARK: styling
  private var backgroundShape: some Shape {
    pageEdge == .fullBleed ? AnyShape(Rectangle()) : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
  
  private var borderOverlay: some View {
    Group {
      switch chrome {
      case .none: EmptyView()
      default:
        backgroundShape.stroke(Color.black.opacity(scheme == .dark ? 0.35 : 0.06), lineWidth: pageEdge == .fullBleed ? 0 : 1)
      }
    }
  }
  
  private var fillStyle: AnyShapeStyle {
    switch chrome {
    case .none:
      return AnyShapeStyle(Color.clear)
      
    case .card:
      return AnyShapeStyle(Color(.secondarySystemBackground))
      
    case .tinted(let colors, let strength):
      let clamped = min(max(strength, 0), 1)
      let baseOpacity = scheme == .dark ? 0.35 : 0.24
      let opacity = baseOpacity * (0.7 + 0.3 * clamped)
      
      if colors.count == 1 {
        return AnyShapeStyle(colors[0].opacity(opacity))
      } else {
        let grad = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        return AnyShapeStyle(grad.opacity(opacity))
      }
    }
  }
  
  private var shadowColor: Color { pageEdge == .fullBleed ? .clear : Color.black.opacity(scheme == .dark ? 0.35 : 0.12) }
  private var shadowRadius: CGFloat { pageEdge == .fullBleed ? 0 : 6 }
}

// tiny helper to erase Shape type
struct AnyShape: Shape {
  private let _path: (CGRect) -> Path
  init<S: Shape>(_ shape: S) { _path = { shape.path(in: $0) } }
  func path(in rect: CGRect) -> Path { _path(rect) }
}

// Only attach matchedGeometryEffect when requested.
// (Prevents months “disappearing” when both hierarchies try to match all items.)
private struct MatchedIfNeeded: ViewModifier {
  let id: AnyHashable
  let ns: Namespace.ID
  let isMatched: Bool
  let isSource: Bool
  
  func body(content: Content) -> some View {
    if isMatched {
      content.matchedGeometryEffect(id: id, in: ns, isSource: isSource)
    } else {
      content
    }
  }
}
