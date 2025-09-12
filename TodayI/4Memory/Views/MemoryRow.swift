import SwiftUI

struct MemoryRow: View {
  @Bindable var memory: MemoryModel
  let isPremium: Bool
  var onMore: (() -> Void)? = nil
  var onTapImage: ((Int) -> Void)? = nil
  
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.modelContext) private var context
  @Environment(\.colorScheme) private var scheme
  
  private var canEditPrivacy: Bool {
    (auth.userID ?? "") == memory.userID && auth.userID != nil
  }
  
  private var timeString: String {
    // If you have your own formatter, keep it. Otherwise this is a nice default:
    DateFormatter.localizedString(from: memory.date, dateStyle: .medium, timeStyle: .short)
  }
  
  var body: some View {
    let moodColor = memory.mood.adaptiveColor
    
    VStack(alignment: .leading, spacing: 12) {
      
      // 0) Privacy badge at the very top-right
      if canEditPrivacy {
        HStack {
          Spacer()
          PrivacyBadge(isPublic: $memory.isPublic)
        }
      }
      
      // 1) Header – “Today I felt {Mood}”
      HStack(alignment: .center, spacing: 12) {
        Text("TodayI felt")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        
        if isPremium {
          Text(memory.mood.rawValue)
            .font(.headline.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
              Capsule().fill(Color(.systemBackground).opacity(0.85))
            )
            .foregroundStyle(moodColor)
            .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
          
          MoodIcon(mood: memory.mood, size: 20)
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
            .foregroundStyle(moodColor)
        }
        .simultaneousGesture(TapGesture().onEnded { onMore?() })
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 12)
      .background(
        (isPremium ? moodColor.opacity(0.25) : moodColor.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      )
      
      // 2) Username + date
      HStack {
        Text("@\(memory.username)")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(timeString)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      
      // 3) Journal text
      if !memory.journalText.isEmpty {
        Text(memory.journalText)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
      }
      
      // 4) Media (replace MediaBlock with your actual component)
      if !memory.mediaSources.isEmpty {
        MediaBlock(sources: memory.mediaSources, onTap: onTapImage)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      
      // 5) Actions / flags
      HStack(spacing: 20) {
        Button { } label: { Label("Like", systemImage: "hand.thumbsup") }
        Button { } label: { Label("Comment", systemImage: "text.bubble") }
        Spacer()
        PremiumPill(isPremium: isPremium)
      }
      .font(.subheadline.weight(.semibold))
      .padding(.top, 4)
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }
}

#Preview("MemoryRow – Owner (toggle enabled)") {
  // Mock memory
  let m = MemoryModel(
    userID: "abc123",
    username: "kemuel",
    date: .now,
    mood: .happy,
    journalText: "Great run today!",
    downloadURLs: ["photo"],  // SF Symbol stand-in
    isPublic: false
  )
  
  // Mock auth where current user == owner
  let auth = AuthStore()
  auth.userID = "abc123"
  
  return MemoryRow(memory: m, isPremium: true)
    .environmentObject(auth)
    .padding()
}

#Preview("MemoryRow – Not owner (read-only)") {
  let m = MemoryModel(
    userID: "owner-id",
    username: "todayi_user",
    date: .now,
    mood: .sad,
    journalText: "Tough morning, but hanging in there.",
    isPublic: true
  )
  
  let auth = AuthStore()
  auth.userID = "viewer-id"
  
  return MemoryRow(memory: m, isPremium: false)
    .environmentObject(auth)
    .padding()
}
