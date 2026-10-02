//
//  GlobalFeedService_Sample.swift
//  TodayI
//

#if DEBUG
import Foundation

/// A believable World feed for App Store screenshots, behind the `-sampleFeed` launch
/// argument. `generateTestPage` is for exercising layout ("Test post #3" from "@user3")
/// and reads as fake in a listing; this one reads like a real day.
///
/// Nothing here touches Firestore. Rows are upserted into SwiftData when they draw, like
/// any feed row, so their ids carry `SwiftDataManager.sampleIDPrefix` and turning the
/// sample year off in Settings removes them with everything else it seeded.
extension GlobalFeedService {

  static var usesSampleFeed: Bool {
    ProcessInfo.processInfo.arguments.contains("-sampleFeed")
  }

  /// A day's worth of tallies, so the chart reads like a real crowd rather than the
  /// dozen posts on screen.
  static let sampleTally: [Mood: Int] = [
    .happy: 412, .neutral: 288, .sad: 197, .surprise: 151,
    .angry: 96, .fear: 83, .disgust: 54,
  ]

  static func generateSamplePage(for day: Date) -> GlobalFeedPage {
    let cal = Calendar(identifier: .gregorian)
    let dayKey = day.formattedDayKeyLocal()
    let tzID = TimeZone.current.identifier

    let items = samplePosts.enumerated().map { index, post in
      // Morning times before the screenshots' 9:41 status bar, newest first.
      let created = cal.date(byAdding: .minute, value: 9 * 60 + 38 - index * 19,
                             to: cal.startOfDay(for: day)) ?? day
      return MemoryDTO(
        id: SwiftDataManager.sampleIDPrefix + "feed-\(index)",
        username: post.username,
        userID: SwiftDataManager.sampleIDPrefix + post.username,
        date: day,
        mood: post.mood.rawValue,
        journalText: post.text,
        likes: post.likes,
        likedBy: [],
        // Specific Picsum (Unsplash-licensed) photos chosen to match each caption; a
        // seeded URL is still a random photo, which put a night skyline under "coffee".
        remoteImagePaths: post.photoID.map { ["https://picsum.photos/id/\($0)/1080/1350"] } ?? [],
        videoRemoteURL: nil,
        linkURL: nil,
        isPublic: true,
        isPremium: post.isPremium,
        createdAt: created,
        updatedAt: created,
        authorTZ: tzID,
        dayKey: dayKey
      )
    }
    return GlobalFeedPage(items: items, lastSnapshot: nil)
  }

  private struct SamplePost {
    let username: String
    let mood: Mood
    let text: String
    let likes: Int
    let photoID: Int?
    let isPremium: Bool
  }

  private static let samplePosts: [SamplePost] = [
    .init(username: "sunnyside.jo", mood: .happy,
          text: "First sunny morning in two weeks. Coffee on the balcony before anyone else woke up.",
          likes: 48, photoID: 431, isPremium: true),
    .init(username: "quietkettle", mood: .neutral,
          text: "Nothing special today, and honestly that felt nice.",
          likes: 12, photoID: nil, isPremium: false),
    .init(username: "rainyday.ren", mood: .sad,
          text: "Missing my grandma a lot today. Made her ginger tea and it helped a little.",
          likes: 67, photoID: 326, isPremium: false),
    .init(username: "kai.writes", mood: .surprise,
          text: "Got a letter from an old friend. An actual letter, with a stamp!",
          likes: 31, photoID: nil, isPremium: true),
    .init(username: "latebloomer", mood: .happy,
          text: "Ran my first 5K without stopping. Slow, but I did it.",
          likes: 89, photoID: 568, isPremium: false),
    .init(username: "mossandfern", mood: .fear,
          text: "Starting a new job on Monday. Excited and terrified in equal parts.",
          likes: 24, photoID: nil, isPremium: false),
    .init(username: "bea.notes", mood: .angry,
          text: "Two hours on hold for a five-minute fix. Breathing it out.",
          likes: 19, photoID: nil, isPremium: true),
  ]
}
#endif
