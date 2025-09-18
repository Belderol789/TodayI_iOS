import SwiftUI

struct GlassMoodFilter: View {
  @ObservedObject var vm: GlobalFeedViewModel
  
  private let glass = RoundedRectangle(cornerRadius: 14, style: .continuous)
  
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        allPill
        ForEach(Mood.allCases) { mood in
          moodPill(mood)
        }
      }
      .padding(8)
      .background(.ultraThinMaterial, in: glass)
      .overlay(glass.stroke(.white.opacity(0.12)))
      .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
      .padding(.horizontal, 16)
    }
  }
  
  // MARK: - Pills
  
  private var allPill: some View {
    let isSelected = vm.selectedMoods.isEmpty
    let total = vm.totalCount
    let pctText = total > 0 ? "100%" : "0%"
    
    return Button {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
        vm.clearMoodFilter()
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "circle.grid.2x2")
          .imageScale(.medium)
        Text("All")
        Text(pctText).foregroundStyle(.secondary)
      }
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(
        Capsule().fill((isSelected ? Color.accentColor : .clear).opacity(0.22))
      )
      .overlay(
        Capsule().stroke(.white.opacity(isSelected ? 0.25 : 0.08), lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(total == 0 && !isSelected)
    .opacity(total == 0 && !isSelected ? 0.45 : 1)
  }
  
  private func moodPill(_ mood: Mood) -> some View {
    let pct = vm.percentage(for: mood)
    let isSelected = vm.selectedMoods.contains(mood)   // ✅ multi-select
    let disabled = (pct == 0 && !isSelected)
    
    return Button {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
        vm.toggleMood(mood)  // ✅ new multi-select toggle
      }
    } label: {
      HStack(spacing: 6) {
        MoodIcon(mood: mood, size: 20)
        Text("\(pct)%").foregroundStyle(.secondary)
      }
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(
        Capsule().fill((isSelected ? mood.adaptiveColor : .clear).opacity(0.22))
      )
      .overlay(
        Capsule().stroke(.white.opacity(isSelected ? 0.25 : 0.08), lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.45 : 1)
  }
}
