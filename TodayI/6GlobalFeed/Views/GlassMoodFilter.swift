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
          .fontWeight(.semibold)
      }
      .font(.subheadline)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        Capsule().fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07))
      )
      .foregroundStyle(isSelected ? Color.accentColor : .secondary)
      .overlay(
        Capsule().stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
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
      HStack(spacing: 5) {
        MoodIcon(mood: mood, size: 18)
        if pct > 0 {
          Text("\(pct)%")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? mood.adaptiveColor : .secondary)
        }
      }
      .font(.subheadline)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        Capsule().fill(isSelected ? mood.adaptiveColor.opacity(0.18) : Color.primary.opacity(0.07))
      )
      .overlay(
        Capsule().stroke(isSelected ? mood.adaptiveColor.opacity(0.4) : Color.clear, lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.35 : 1)
    .accessibilityLabel(mood.rawValue)
    .accessibilityValue(isSelected ? "Selected, \(pct)%" : "\(pct)%")
  }
}
