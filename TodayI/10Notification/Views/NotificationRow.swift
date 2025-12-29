import SwiftUI

struct NotificationRow: View {
  let notification: AppNotificationDTO
  let onTap: () -> Void
  
  // MARK: Icon + accent (only used subtly)
  private var iconName: String {
    switch notification.type {
    case "like_milestone": return "heart.fill"
    case "comment_milestone": return "text.bubble.fill"
    default: return "bell.fill"
    }
  }
  private var accent: Color {
    switch notification.type {
    case "like_milestone": return .red
    case "comment_milestone": return .blue
    default: return .gray
    }
  }
  
  // MARK: Containers
  private var baseCard: Color { Color(uiColor: .secondarySystemGroupedBackground) }
  private var strokeColor: Color { Color(uiColor: .separator).opacity(0.25) }
  
  var body: some View {
    Button(action: onTap) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: iconName)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(accent)
          .padding(.top, 4)
        
        VStack(alignment: .leading, spacing: 4) {
          Text(notification.title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(2)
          
          Text(notification.body)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
          
          Text(notification.createdAt, style: .relative)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        
        Spacer()
        
        // Unread dot
        Circle()
          .fill(accent)
          .frame(width: 8, height: 8)
          .opacity(notification.read ? 0 : 1)
          .padding(.top, 6)
      }
      .contentShape(Rectangle())
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .background(
        // Base card
        RoundedRectangle(cornerRadius: 12)
          .fill(baseCard)
        // Very light type-tinted wash only when unread
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .fill(accent.opacity(notification.read ? 0 : 0.06))
          )
        // 1px separator stroke for definition
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(strokeColor, lineWidth: 1)
          )
        // Tiny elevation only when unread
          .shadow(color: Color.black.opacity(notification.read ? 0 : 0.06),
                  radius: 8, x: 0, y: 2)
      )
    }
    .buttonStyle(.plain)
    // optional press feel (subtle)
    .animation(.easeOut(duration: 0.15), value: notification.read)
  }
}

#Preview("Unread Like") {
  NotificationRow(notification: .sampleLike) {}
    .padding()
    .previewLayout(.sizeThatFits)
}

#Preview("Read Comment") {
  NotificationRow(notification: .sampleComment) {}
    .padding()
    .previewLayout(.sizeThatFits)
}
