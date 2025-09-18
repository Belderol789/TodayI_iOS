import SwiftUI

struct MemoryRow: View {
  @Bindable var memory: MemoryModel
  let isPremium: Bool
  var onMore: (() -> Void)? = nil
  var onTapImage: ((Int) -> Void)? = nil
  
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.modelContext) private var context
  @Environment(\.colorScheme) private var scheme
  
  private var canEditPrivacy: Bool { auth.userID == memory.userID }
  private var timeString: String { DateFormatter.shortDateFormatter.string(from: memory.date) }
  
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
          .font(.subheadline.bold())
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
        Group {
          if isPremium {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay(
                LinearGradient(
                  colors: [
                    moodColor.opacity(0.25),
                    moodColor.opacity(0.10)
                  ],
                  startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              )
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(moodColor.opacity(0.15), lineWidth: 1)
              )
          } else {
            moodColor.opacity(0.15)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
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
      
      // 4) Media (video -> images -> link)
      if let video = memory.videoSource {
        MediaTile(source: video, cornerRadius: 14, minHeight: 220)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear,
                  radius: isPremium ? 10 : 0, x: 0, y: 6)
        
      } else if !memory.imageSources.isEmpty {
        MediaBlock(sources: memory.imageSources, onTap: onTapImage)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: isPremium ? moodColor.opacity(0.12) : .clear,
                  radius: isPremium ? 10 : 0, x: 0, y: 6)
      } else if let urlString = memory.linkURL,
                !urlString.isEmpty,
                let url = URL(string: urlString) {
        
        Link(destination: url) {
          LinkPreviewView(url: url)
            .frame(maxWidth: .infinity)              // fill row width (inside the row’s own padding)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)                          // don’t dim on press
      }
      
      // 5) Actions / flags
      HStack(spacing: 10) {
        if isPremium {
          Button {
            // like
          } label: {
            Image(systemName: "hand.thumbsup.fill")
              .padding(.horizontal, 12).padding(.vertical, 8)
              .background(Capsule().fill(memory.mood.adaptiveColor.opacity(0.18)))
              .foregroundStyle(moodColor)
          }
          .buttonStyle(.plain)
          
          Button {
            // comment
          } label: {
            Image(systemName: "text.bubble.fill")
              .padding(.horizontal, 12).padding(.vertical, 8)
              .background(Capsule().fill(moodColor.opacity(0.18)))
              .foregroundStyle(moodColor)
          }
          .buttonStyle(.plain)
        } else {
          Button { } label: {
            Image(systemName: "hand.thumbsup")
              .foregroundStyle(moodColor)
          }
          Button { } label: {
            Image(systemName: "text.bubble")
              .foregroundStyle(moodColor)
          }
        }
        
        Spacer()
        PremiumPill(isPremium: isPremium)
      }
      .font(.subheadline.weight(.semibold))
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)   // 👈 add this
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemBackground))
        .overlay(
          // Premium only: soft gradient stroke
          Group {
            if isPremium {
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                  LinearGradient(
                    colors: [memory.mood.adaptiveColor.opacity(0.6),
                             memory.mood.adaptiveColor.opacity(0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                  ),
                  lineWidth: 1.2
                )
                .blendMode(.overlay)
            }
          }
        )
        .shadow(color: isPremium ? memory.mood.adaptiveColor.opacity(0.12) : .clear,
                radius: isPremium ? 10 : 0, x: 0, y: 6)
    )
    .overlay(alignment: .topLeading) {          // 👈 add here
      if isPremium {
        MoodIcon(mood: memory.mood, size: 20)
          .offset(x: 14, y: 10)
          .opacity(0.9)
      }
    }
  }
}
