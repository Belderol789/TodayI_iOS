import SwiftUI

struct MemoryRow: View {
  @Bindable var memory: MemoryModel
  var onMore: (() -> Void)? = nil
  var onTapImage: ((Int) -> Void)? = nil
  
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.modelContext) private var context
  @Environment(\.colorScheme) private var scheme
  
  private var canEditPrivacy: Bool { auth.userID == memory.userID }
  private var timeString: String { DateFormatter.shortDateFormatter.string(from: memory.date) }
  private var isPremium: Bool { memory.isPremium }
  
  var body: some View {
    let moodColor = memory.mood.adaptiveColor
    
    VStack(alignment: .leading, spacing: 12) {
      // 0) Privacy badge
      if canEditPrivacy {
        HStack { Spacer(); PrivacyBadge(isPublic: $memory.isPublic) }
      }
      
      // 2) Username + date
      HStack {
        if isPremium {
          MoodIcon(mood: memory.mood, size: 20).opacity(0.9)
        }
        Text("@\(memory.username)").font(.subheadline.weight(.semibold))
        Spacer()
        Text(timeString).font(.caption).foregroundStyle(.secondary)
      }
      
      // 1) Header
      HStack(alignment: .center, spacing: 12) {
        Text("TodayI felt")
          .font(.subheadline.bold())
          .foregroundStyle(.secondary)
        
        if isPremium {
          Text(memory.mood.rawValue)
            .font(.headline.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.systemBackground).opacity(0.85)))
            .foregroundStyle(moodColor)
            .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
        } else {
          Text(memory.mood.rawValue)
            .font(.headline.bold())
            .foregroundStyle(moodColor)
        }
        
        Spacer(minLength: 0)
        Menu {
          Button("Edit") { /* hook up later */ }
          Button("Delete", role: .destructive) { /* hook up later */ }
        } label: {
          Image(systemName: "ellipsis.circle")
            .imageScale(.large)
            .foregroundStyle(Color.secondary)
        }
        .simultaneousGesture(TapGesture().onEnded { onMore?() })
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(isPremium ? Color.white.opacity(0.08) : moodColor.opacity(0.15))
          .overlay {
            if isPremium {
              LinearGradient(
                colors: [moodColor.opacity(0.20), moodColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
          }
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(moodColor.opacity(isPremium ? 0.18 : 0.15), lineWidth: 1)
          )
      )
      
      // 3) Journal text
      if !memory.journalText.isEmpty {
        Text(memory.journalText)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      
      // 4) Media (video -> images -> link)
      if let video = memory.videoSource {
        MediaTile(source: video, cornerRadius: 14, minHeight: 220)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear, radius: isPremium ? 10 : 0, x: 0, y: 6)
        
      } else if !memory.imageSources.isEmpty {
        MediaBlock(sources: memory.imageSources, onTap: onTapImage)
          .frame(maxWidth: .infinity)
          .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear, radius: isPremium ? 10 : 0, x: 0, y: 6)
        
      } else if let urlString = memory.linkURL, !urlString.isEmpty, let url = URL(string: urlString) {
        Link(destination: url) {
          LinkPreviewView(url: url)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
      }
      
      // 5) Actions / flags
      HStack(spacing: 10) {
        if isPremium {
          Button { } label: {
            Image(systemName: "hand.thumbsup.fill")
              .padding(.horizontal, 12).padding(.vertical, 8)
              .background(Capsule().fill(moodColor.opacity(0.18)))
              .foregroundStyle(moodColor)
          }.buttonStyle(.plain)
          
          Button { } label: {
            Image(systemName: "text.bubble.fill")
              .padding(.horizontal, 12).padding(.vertical, 8)
              .background(Capsule().fill(moodColor.opacity(0.18)))
              .foregroundStyle(moodColor)
          }.buttonStyle(.plain)
        } else {
          Button { } label: { Image(systemName: "hand.thumbsup").foregroundStyle(moodColor) }
          Button { } label: { Image(systemName: "text.bubble").foregroundStyle(moodColor) }
        }
        
        Spacer()
        PremiumPill(isPremium: isPremium)
      }
      .font(.subheadline.weight(.semibold))
      .padding(.top, 4)
    }
    .padding(14)                                        // inner content padding
    .frame(maxWidth: .infinity, alignment: .leading)
    .premiumMoodCard(color: moodColor, isPremium: isPremium, scheme: scheme) // 👈 NEW
  }
}
