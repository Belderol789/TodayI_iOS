import SwiftUI
import Charts

struct MoodPieChart: View {
  let slices: [MoodSlice]
  let total: Int
  let title: String
  @Binding var tabSelection: AppTab
  
  // Animation drivers (unchanged)
  @State private var progress: CGFloat = 0
  private let perSliceDelay: CGFloat = 0.06
  private let perSliceRamp: CGFloat = 0.35
  
  var body: some View {
    VStack(spacing: 8) {
      Header(title: title)
      
      ZStack {
        if total == 0 {
          EmptyState {
            tabSelection = .create
          }
          .transition(.opacity)
        } else {
          ChartArea(
            slices: slices,
            total: total,
            progress: progress,
            perSliceDelay: perSliceDelay,
            perSliceRamp: perSliceRamp
          )
          .transition(.scale.combined(with: .opacity))
          
          DominantBadges(
            slices: slices,
            progress: progress
          )
        }
      }
      .scaleEffect(progress < 1 ? 0.98 : 1.0) // subtle bloom
      .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .onAppear { restartAnimation() }
    .onChange(of: slices, { _, _ in
      restartAnimation()
    })
    .onChange(of: total, { _, _ in
      restartAnimation()
    })
  }
}

// MARK: - Subviews

private struct Header: View {
  
  let title: String
  
  var body: some View {
    Text(title)
      .font(.title3).fontWeight(.semibold)
      .multilineTextAlignment(.center)
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, alignment: .center)
  }
}

private struct EmptyState: View {
  var onCreate: () -> Void
  
  init(onCreate: @escaping () -> Void) {
    self.onCreate = onCreate
  }
  
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "face.smiling")
        .resizable().scaledToFit()
        .frame(width: 44, height: 44)
        .foregroundStyle(.secondary)
      
      Text("Be the world's first mood today!")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      
      Button(action: onCreate) {
        Text("Create a Memory")
          .font(.headline)
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Capsule().fill(Color.accentColor))
          .foregroundColor(.white)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 240)
  }
}

private struct ChartArea: View {
  let slices: [MoodSlice]
  let total: Int
  let progress: CGFloat
  let perSliceDelay: CGFloat
  let perSliceRamp: CGFloat
  
  var body: some View {
    Chart(indexedSlices, id: \.slice.id) { pair in
      let idx = pair.index
      let slice = pair.slice
      let p = sliceProgress(index: idx)
      
      SectorMark(
        angle: .value("Count", Double(slice.count) * Double(p)),
        innerRadius: .ratio(0.55),
        outerRadius: .inset(0)
      )
      .foregroundStyle(slice.mood.adaptiveColor)
      .annotation(position: .overlay, alignment: .center) {
        let pct = total > 0 ? Double(slice.count) / Double(total) : 0
        if pct >= 0.07 {
          Text("\(Int(round(pct * 100)))%")
            .font(.caption2).bold()
            .foregroundStyle(.white)
            .opacity(Double(p)) // fade in with wedge
        }
      }
    }
    .chartLegend(position: .bottom, alignment: .center)
    .opacity(Double(max(0.001, progress))) // legend fade-in without jump
    .animation(.easeOut(duration: 0.25), value: progress)
    .frame(maxWidth: .infinity, minHeight: 240)
  }
  
  // MARK: - Helpers local to ChartArea
  
  private var indexedSlices: [(index: Int, slice: MoodSlice)] {
    slices.enumerated().map { (index, slice) in
      (index: index, slice: slice)
    }
  }
  
  private func sliceProgress(index: Int) -> CGFloat {
    let start = CGFloat(index) * perSliceDelay
    let t = (progress - start) / perSliceRamp
    return clamp(t, 0, 1)
  }
  
  private func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
    min(max(x, a), b)
  }
}

private struct DominantBadges: View {
  let slices: [MoodSlice]
  let progress: CGFloat
  
  var body: some View {
    if let topCount = slices.map(\.count).max(), topCount > 0 {
      let tops = slices.filter { $0.count == topCount }
      HStack(alignment: .center, spacing: -8) {
        ForEach(tops) { top in
          VStack(spacing: 4) {
            top.mood.image
              .resizable().scaledToFit()
              .frame(width: 32, height: 32)
              .foregroundStyle(top.mood.adaptiveColor)
            Text("\(topCount)")
              .font(.headline).bold()
              .foregroundStyle(.primary)
          }
        }
      }
      .opacity(Double(clamp((progress - 0.3) / 0.4, 0, 1)))
    }
  }
  
  private func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
    min(max(x, a), b)
  }
}

// MARK: - Private helpers on main view

private extension MoodPieChart {
  func restartAnimation() {
    progress = 0
    withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
      progress = 1
    }
  }
}
