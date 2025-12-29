import SwiftUI
import Charts

struct YearMoodBarsView: View {
  /// Pass in the already-fetched DateModels for the year
  @Binding var models: [DateModel]
  /// Optional year label for the header (purely cosmetic)
  var year: Int? = nil
  
  // Animation state
  @State private var animatedValues: [Mood: Int] = [:]
  @State private var shownIcons: [Mood: Bool] = [:]
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      content
    }
    .padding()
    .onAppear { triggerBarAnimation() }
    .onChange(of: models) { _, _ in triggerBarAnimation() }
  }
}

// MARK: - Sections
private extension YearMoodBarsView {
  @ViewBuilder
  var content: some View {
    if moodCounts.isEmpty {
      Text("No moods recorded\(year.map { " for \($0)" } ?? "").")
        .foregroundStyle(.secondary)
        .padding(.top, 24)
    } else {
      chartView
    }
  }
  
  var chartView: some View {
    Chart {
      ForEach(sortedMoodCounts, id: \.key) { item in
        barMark(for: item)
          .annotation(position: .trailing, alignment: .trailing) {
            barAnnotation(for: item)
          }
      }
    }
    .chartXAxis(.hidden) // counts shown in annotations; hide tiny axis
    .chartPlotStyle { plot in
      plot.padding(.bottom, 10).padding(.top, 4).padding(.trailing, 8)
    }
    .chartYScale(range: .plotDimension(padding: 8))
    .frame(height: chartHeight)
    .padding(.bottom, 4)
  }
}

// MARK: - Header
private extension YearMoodBarsView {
  var header: some View {
    HStack {
      Text("Moods\(year.map { " in \($0)" } ?? "")")
        .font(.headline)
      Spacer()
    }
  }
}

// MARK: - Chart pieces
private extension YearMoodBarsView {
  @ChartContentBuilder
  func barMark(for item: (key: Mood, value: Int)) -> some ChartContent {
    let animatedValue: Int = animatedValues[item.key] ?? 0
    BarMark(
      x: .value("Count", animatedValue),
      y: .value("Mood", item.key.rawValue)
    )
    .foregroundStyle(item.key.adaptiveColor)
  }
  
  func barAnnotation(for item: (key: Mood, value: Int)) -> some View {
    HStack(spacing: 6) {
      Text("\(item.value)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .opacity((animatedValues[item.key] ?? 0) > 0 ? 1 : 0)
      
      item.key.image
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 14, height: 14)
        .foregroundStyle(item.key.adaptiveColor)
        .scaleEffect(shownIcons[item.key] == true ? 1.0 : 0.6)
        .opacity(shownIcons[item.key] == true ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7),
                   value: shownIcons[item.key] == true)
    }
  }
}

// MARK: - Derived data
private extension YearMoodBarsView {
  var moodCounts: [Mood: Int] {
    var counts: [Mood: Int] = [:]
    for model in models {
      for mood in model.moods {
        counts[mood, default: 0] += 1
      }
    }
    return counts
  }
  
  var sortedMoodCounts: [(key: Mood, value: Int)] {
    moodCounts.sorted { a, b in
      a.value != b.value ? a.value > b.value : a.key.rawValue < b.key.rawValue
    }
  }
  
  var chartHeight: CGFloat {
    let rowHeight: CGFloat = 28
    return max(220, rowHeight * CGFloat(sortedMoodCounts.count) + 36)
  }
}

// MARK: - Animation
private extension YearMoodBarsView {
  func triggerBarAnimation() {
    animatedValues = [:]
    shownIcons = [:]
    
    // animate bars left→right and stagger icons
    for (index, item) in sortedMoodCounts.enumerated() {
      let delay = 0.1 + Double(index) * 0.05
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        withAnimation(.easeOut(duration: 0.6)) {
          animatedValues[item.key] = item.value
        }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) {
        shownIcons[item.key] = true
      }
    }
  }
}
