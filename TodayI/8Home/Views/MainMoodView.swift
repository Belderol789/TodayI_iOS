import SwiftUI

// 1) Add this PreferenceKey somewhere in the file (outside the struct)
private struct TitleSizeKey: PreferenceKey {
  static var defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
    value = nextValue()
  }
}

struct MainMoodView: View {
  @Binding var models: [DateModel]
  var year: Int? = nil
  
  // Layout
  private let iconSize: CGFloat = 72
  private let overlap: CGFloat = 28
  
  // Shimmer
  @State private var shimmerProgress: CGFloat = 0
  @State private var shimmerTimer: Timer?
  @State private var titleSize: CGSize = .zero
  
  var body: some View {
    VStack(spacing: 10) {
      titleView
      
      if topMoods.isEmpty {
        Text("No moods recorded\(year.map { " for \($0)" } ?? "").")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        // Overlapping icons, no labels/numbers
        HStack(spacing: -overlap) {
          ForEach(topMoods, id: \.rawValue) { mood in
            mood.image
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: iconSize, height: iconSize)
              .foregroundStyle(mood.adaptiveColor)
              .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
              )
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              .shadow(radius: 1, y: 1)
          }
        }
        .fixedSize() // don’t expand parent horizontally
      }
    }
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .center)
    // In body
    .onAppear {
      startSingleShimmerCycle() // immediate pass
      shimmerTimer?.invalidate()
      shimmerTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
        startSingleShimmerCycle()
      }
    }
    .onDisappear {
      shimmerTimer?.invalidate()
      shimmerTimer = nil
    }
    .onChange(of: models) { _, _ in
      startSingleShimmerCycle()
    }
  }
  
  func startSingleShimmerCycle() {
    shimmerProgress = 0
    withAnimation(.easeInOut(duration: 1.6)) {
      shimmerProgress = 1
    }
  }
}

// MARK: - Title
// 3) Replace your `titleView` with this measured version
private extension MainMoodView {
  var titleView: some View {
    // Build once so styles/metrics are identical for text + mask
    let baseTitle =
    Text(titleText)
      .font(.title3.weight(.semibold))
      .foregroundStyle(titleStyle)
      .fixedSize(horizontal: true, vertical: true) // prevent truncation/ellipsis
    // Measure the *intrinsic* size of the text
      .background(
        GeometryReader { geo in
          Color.clear
            .preference(key: TitleSizeKey.self, value: geo.size)
        }
      )
    
    return baseTitle
    // Consume the measured size
      .onPreferenceChange(TitleSizeKey.self) { titleSize = $0 }
    // Shimmer overlay precisely aligned to the measured title size
      .overlay(alignment: .center) {
        if titleSize != .zero {
          let w = titleSize.width
          let h = titleSize.height
          let stripeW = w * 0.45
          let offsetX = shimmerProgress * (w + stripeW) - stripeW
          
          ShimmerStripe()
            .frame(width: stripeW, height: h * 1.2)
            .offset(x: offsetX)
            .compositingGroup()
            .mask(
              Text(titleText)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: true, vertical: true)
                .frame(width: w, height: h, alignment: .center)
            )
            .allowsHitTesting(false)
        }
      }
  }
  
  var titleText: String {
    if topMoods.isEmpty { return "—" }
    if topMoods.count == 1 { return displayName(for: topMoods[0]) }
    return "Multiple"
  }
  
  var titleStyle: AnyShapeStyle {
    if topMoods.count == 1, let mood = topMoods.first {
      return AnyShapeStyle(mood.adaptiveColor)
    } else if !topMoods.isEmpty {
      return AnyShapeStyle(
        LinearGradient(
          colors: topMoods.map { $0.adaptiveColor },
          startPoint: .leading, endPoint: .trailing
        )
      )
    } else {
      return AnyShapeStyle(.secondary)
    }
  }
}

// MARK: - Shimmer stripe
private struct ShimmerStripe: View {
  var body: some View {
    LinearGradient(
      colors: [
        .clear,
        .white.opacity(0.18),
        .white.opacity(0.34),
        .white.opacity(0.18),
        .clear
      ],
      startPoint: .topLeading, endPoint: .bottomTrailing
    )
    .blur(radius: 2)
  }
}

// MARK: - Derivations
private extension MainMoodView {
  var moodCounts: [Mood: Int] {
    var counts: [Mood: Int] = [:]
    for model in models { for mood in model.moods { counts[mood, default: 0] += 1 } }
    return counts
  }
  
  var topMoods: [Mood] {
    guard let maxCount = moodCounts.values.max(), maxCount > 0 else { return [] }
    return moodCounts
      .filter { $0.value == maxCount }
      .map(\.key)
      .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
  }
  
  func displayName(for mood: Mood) -> String {
    mood.rawValue.capitalized
  }
}
