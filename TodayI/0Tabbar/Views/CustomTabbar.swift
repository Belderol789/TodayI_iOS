// MARK: - Custom floating tab bar
import SwiftUI

struct CustomTabBar: View {
  @Binding var selection: AppTab
  let namespace: Namespace.ID
  @Environment(\.colorScheme) private var scheme
  
  @ViewBuilder
  private var backgroundView: some View {
    if #available(iOS 17.0, *) {
      Rectangle().fill(.ultraThinMaterial)
    } else {
      Rectangle().fill(
        Color(.systemBackground).opacity(scheme == .dark ? 0.35 : 0.9)
      )
    }
  }
  
  var body: some View {
    HStack(spacing: 12) {
      ForEach(AppTab.allCases) { tab in
        TabButton(tab: tab,
                  isSelected: tab == selection,
                  namespace: namespace) {
          if tab != selection {
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.impactOccurred()
          }
          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selection = tab
          }
        }
                  .frame(maxWidth: .infinity)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .background(backgroundView)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
