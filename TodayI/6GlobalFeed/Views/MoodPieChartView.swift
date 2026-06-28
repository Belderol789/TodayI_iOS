import SwiftUI
import Charts

struct MoodPieChart: View {
  let slices: [MoodSlice]
  let total: Int
  let selectedMoods: Set<Mood>
  let title: String
  @Binding var tabSelection: AppTab

  @State private var progress: CGFloat = 0
  private let perSliceDelay: CGFloat = 0.06
  private let perSliceRamp: CGFloat = 0.35

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Title + date on the same row
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.headline.weight(.bold))
          .foregroundStyle(.primary)
        Spacer()
        Text(Date().formatted("MMM d"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if total == 0 {
        EmptyChartState { tabSelection = .create }
      } else {
        HStack(spacing: 20) {
          // Donut chart
          ZStack {
            ChartArea(
              slices: slices,
              selectedMoods: selectedMoods,
              total: total,
              progress: progress,
              perSliceDelay: perSliceDelay,
              perSliceRamp: perSliceRamp
            )
            .frame(width: 140, height: 140)

            // Clean center: total count only
            VStack(spacing: 2) {
              Text("\(total)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
              Text("today")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .opacity(Double(clamp((progress - 0.4) / 0.4, 0, 1)))
          }

          // Legend
          moodLegend
        }
      }
    }
    .scaleEffect(progress < 1 ? 0.98 : 1.0)
    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
    .onAppear { restartAnimation() }
    .onChange(of: slices) { _, _ in restartAnimation() }
    .onChange(of: total) { _, _ in restartAnimation() }
  }

  // MARK: - Legend

  private var moodLegend: some View {
    let sorted = slices.sorted { $0.count > $1.count }
    return VStack(alignment: .leading, spacing: 6) {
      ForEach(sorted.prefix(5)) { slice in
        let pct = total > 0 ? Int((Double(slice.count) / Double(total) * 100).rounded()) : 0
        let dimmed = !selectedMoods.isEmpty && !selectedMoods.contains(slice.mood)
        HStack(spacing: 6) {
          Circle()
            .fill(slice.mood.adaptiveColor)
            .frame(width: 8, height: 8)
          Text(slice.mood.rawValue.capitalized)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
          Spacer()
          Text("\(pct)%")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .opacity(dimmed ? 0.35 : 1)
      }
    }
    .opacity(Double(clamp((progress - 0.2) / 0.5, 0, 1)))
    .frame(maxWidth: .infinity)
  }

  private func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
    min(max(x, a), b)
  }

  private func restartAnimation() {
    progress = 0
    withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
      progress = 1
    }
  }
}

// MARK: - Chart area

private struct ChartArea: View {
  let slices: [MoodSlice]
  let selectedMoods: Set<Mood>
  let total: Int
  let progress: CGFloat
  let perSliceDelay: CGFloat
  let perSliceRamp: CGFloat

  var body: some View {
    Chart(indexedSlices, id: \.slice.id) { pair in
      let idx = pair.index
      let slice = pair.slice
      let p = sliceProgress(index: idx)
      let dimmed = !selectedMoods.isEmpty && !selectedMoods.contains(slice.mood)

      SectorMark(
        angle: .value("Count", Double(slice.count) * Double(p)),
        innerRadius: .ratio(0.58),
        outerRadius: .inset(2),
        angularInset: 1.5
      )
      .foregroundStyle(slice.mood.adaptiveColor.opacity(dimmed ? 0.25 : 1))
    }
    .chartLegend(.hidden)
    .opacity(Double(max(0.001, progress)))
    .animation(.easeOut(duration: 0.25), value: progress)
  }

  private var indexedSlices: [(index: Int, slice: MoodSlice)] {
    slices.enumerated().map { ($0.offset, $0.element) }
  }

  private func sliceProgress(index: Int) -> CGFloat {
    let start = CGFloat(index) * perSliceDelay
    let t = (progress - start) / perSliceRamp
    return min(max(t, 0), 1)
  }
}

// MARK: - Empty state

private struct EmptyChartState: View {
  let onCreate: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "face.smiling")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(.secondary)
      Text("Be the first to share\nyour mood today!")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button(action: onCreate) {
        Text("Create a Memory")
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Capsule().fill(Color.accentColor))
          .foregroundColor(.white)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 160)
  }
}
