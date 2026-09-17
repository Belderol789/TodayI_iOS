import SwiftUI

struct GlassMoodFilter: View {
  @ObservedObject var vm: GlobalFeedViewModel

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        allPill
        ForEach(Mood.allCases) { mood in
          moodPill(mood)
        }
      }
      .padding(.horizontal, 16)
    }
  }

  // MARK: - Pills

  private var allPill: some View {
    let isSelected = vm.selectedMoods.isEmpty
    let total = vm.totalCount

    return Button {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
        vm.clearMoodFilter()
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: "square.grid.2x2")
          .imageScale(.small)
        Text("All")
          .font(.subheadline.weight(.semibold))
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .foregroundStyle(isSelected ? .white : Color.accentColor)
      .background(
        Capsule().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(total == 0 && !isSelected)
    .opacity(total == 0 && !isSelected ? 0.4 : 1)
    .accessibilityLabel("All moods")
    .accessibilityValue(isSelected ? "Selected" : "")
  }

  private func moodPill(_ mood: Mood) -> some View {
    let pct = vm.percentage(for: mood)
    let isSelected = vm.selectedMoods.contains(mood)
    let disabled = pct == 0 && !isSelected

    return Button {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
        vm.toggleMood(mood)
      }
    } label: {
      // Matches `CreateMemoryView.moodChip`: icon with a white backing when selected,
      // the mood's name, and a capsule filled with the mood colour.
      HStack(spacing: 5) {
        mood.image
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(isSelected ? 3 : 0)
          .background(Circle().fill(.white.opacity(isSelected ? 0.35 : 0)))
        Text(mood.rawValue)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        if pct > 0 {
          Text("\(pct)%")
            .font(.caption.weight(.semibold))
            .opacity(0.75)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .foregroundStyle(isSelected ? .white : mood.adaptiveColor)
      .background(
        Capsule().fill(isSelected ? mood.adaptiveColor : mood.adaptiveColor.opacity(0.12))
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    .disabled(disabled)
    .opacity(disabled ? 0.35 : 1)
    .accessibilityLabel(mood.rawValue)
    .accessibilityValue(isSelected ? "Selected, \(pct)%" : "\(pct)%")
  }
}
