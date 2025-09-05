import SwiftUI

struct DateView: View {
  @Environment(\.colorScheme) private var scheme
  @Bindable var model: DateModel
  var cornerRadius: CGFloat = 12
  var showsGlow: Bool = false          // ← only glows when true
  
  var body: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(model.moods.gradient(for: scheme))   // <-- gradient background
      .overlay(
        Text(Calendar.current.component(.day, from: model.date).description)
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .shadow(
        color: showsGlow ? Color.primary.opacity(0.7) : .clear,
        radius: showsGlow ? 14 : 0
      )
  }
  
  private func dayString(from date: Date) -> String {
    String(Calendar.current.component(.day, from: date))
  }
}
