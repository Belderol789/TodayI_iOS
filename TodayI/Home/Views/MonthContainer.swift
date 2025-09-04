import SwiftUI

enum MonthChrome {
  case none
  case card
  case tinted(Color, strength: Double = 1)   // strength 0…1 scales the tint
}

// Use this wrapper around a month so it can morph (zoom) between Pager <-> YearGrid
struct MonthContainer<Content: View>: View {
  let month: Date
  let id: AnyHashable
  let zoomNS: Namespace.ID
  let isMatched: Bool
  let isSource: Bool
  let chrome: MonthChrome
  @ViewBuilder var content: Content
  @Environment(\.colorScheme) private var scheme
  
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(fillStyle)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(strokeColor, lineWidth: strokeWidth)
        )
        .shadow(color: shadowColor, radius: shadowRadius, y: 2)
        .modifier(MatchedIfNeeded(id: id, ns: zoomNS, isMatched: isMatched, isSource: isSource))
      
      content.padding(8)
    }
  }
  
  // MARK: - chrome styling
  private var fillStyle: some ShapeStyle {
    switch chrome {
    case .none:
      return Color.clear
    case .card:
      return Color(.secondarySystemBackground)
    case .tinted(let base, let strength):
      let clamped = min(max(strength, 0), 1)
      let baseOpacity = scheme == .dark ? 0.35 : 0.20
      return base.opacity(baseOpacity * (0.6 + 0.4 * clamped))
    }
  }
  
  private var strokeColor: Color {
    switch chrome {
    case .none: return .clear
    default:    return Color.black.opacity(scheme == .dark ? 0.35 : 0.06)
    }
  }
  
  private var strokeWidth: CGFloat {
    if case .none = chrome { return 0 } else { return 1 }
  }
  
  private var shadowColor: Color {
    switch chrome {
    case .none: return .clear
    default:    return Color.black.opacity(scheme == .dark ? 0.35 : 0.12)
    }
  }
  
  private var shadowRadius: CGFloat {
    if case .none = chrome { return 0 } else { return 6 }
  }
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
