import SwiftUI

// MARK: - MemoryRow (social-post style)

struct MemoryRow: View {
  @Environment(\.colorScheme) private var scheme
  let memory: MemoryModel
  let isPremium: Bool
  var onMore: (() -> Void)? = nil
  var onTapImage: ((Int) -> Void)? = nil
  
  private var timeString: String {
    Self.timeFormatter.string(from: memory.date)
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // 1) Mood Banner
      HStack {
        Text("TodayI felt")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        
        if isPremium {
          // Premium: capsule background makes mood pop
          Text(memory.mood.rawValue)
            .font(.headline.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
              Capsule()
                .fill(memory.mood.color(for: scheme))
            )
            .foregroundColor(.white)
        } else {
          // Free: simple mood text in mood color
          Text(memory.mood.rawValue)
            .font(.headline.bold())
            .foregroundColor(memory.mood.color(for: scheme))
        }
        Spacer()
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        (isPremium ? memory.mood.color(for: scheme).opacity(0.25)
         : memory.mood.color(for: scheme).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      )
      
      // 2) Username + Date
      HStack {
        Text(memory.username)
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(timeString)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      
      // 3) Journal Text
      if !memory.journalText.isEmpty {
        Text(memory.journalText)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
      }
      
      // 4) Media (hero or grid)
      if !memory.mediaSources.isEmpty {
        MediaBlock(sources: memory.mediaSources) { index in
          onTapImage?(index)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      
      // 5) Lightweight actions
      HStack(spacing: 20) {
        Button { /* like */ } label: {
          Label("Like", systemImage: "hand.thumbsup")
        }
        Button { /* comment */ } label: {
          Label("Comment", systemImage: "text.bubble")
        }
        Spacer()
        if isPremium {
          Label("Premium", systemImage: "star.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.yellow.opacity(0.2), in: Capsule())
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .padding(.top, 4)
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }
  
  private static let timeFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df
  }()
}

#Preview("MemoryRow – Single Image") {
  let sample = MemoryModel(
    id: UUID().uuidString,
    username: "kemuel",
    date: Date(),
    mood: .happy,
    journalText: "Walked through the park 🌳 and listened to my favorite podcast.",
    localImagePaths: [],
    remoteImagePaths: [],
    downloadURLs: ["photo"],
    createdAt: Date(),
    updatedAt: Date()
  )
  
  MemoryRow(memory: sample, isPremium: false)
    .padding()
}

#Preview("MemoryRow – Gallery") {
  let gallery = MemoryModel(
    id: UUID().uuidString,
    username: "todayi_user",
    date: Date(),
    mood: .surprise,
    journalText: "Weekend highlights with friends 🎉",
    localImagePaths: [],
    remoteImagePaths: [],
    downloadURLs: ["photo", "photo.on.rectangle", "rectangle.stack.person.crop", "film", "mountain.2", "camera.aperture"],
    createdAt: Date(),
    updatedAt: Date()
  )
  
  MemoryRow(memory: gallery, isPremium: true)
    .padding()
}

#Preview("MemoryRow – Long Text") {
  let long = MemoryModel(
    id: UUID().uuidString,
    username: "clyde",
    date: Date(),
    mood: .sad,
    journalText: """
    Today was one of those days where everything seemed to happen at once. \
    I woke up late, spilled coffee on my shirt, and then ran into traffic. \
    But somehow, despite all of that, I made it through feeling oddly grateful. \
    Maybe it’s the small wins that keep us going. ☕️🚦✨
    """,
    localImagePaths: [],
    remoteImagePaths: [],
    downloadURLs: [],
    createdAt: Date(),
    updatedAt: Date()
  )
  
  MemoryRow(memory: long, isPremium: false)
    .padding()
}
