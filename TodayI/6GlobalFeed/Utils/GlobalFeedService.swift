import FirebaseFirestore

struct GlobalFeedPage {
  let items: [MemoryDTO]
  let lastSnapshot: DocumentSnapshot?
}

enum GlobalFeedService {
  
  static func fetchPublicMemories(
    for day: Date,
    pageSize: Int = 30,
    after last: DocumentSnapshot? = nil,
    db: Firestore = .firestore()
  ) async throws -> GlobalFeedPage {
    
    let dayKey = day.formattedDayKeyLocal()   // you chose local-only keys
    
    var q: Query = db.collectionGroup("memories")
      .whereField("isPublic", isEqualTo: true)
      .whereField("dayKey", isEqualTo: dayKey)
      .limit(to: pageSize)
    
    if let last { q = q.start(afterDocument: last) }
    
    let snap = try await q.getDocuments()
    
    var items: [MemoryDTO] = []
    items.reserveCapacity(snap.documents.count)
    for doc in snap.documents {
      if let dto = try? doc.data(as: MemoryDTO.self) {
        items.append(dto)
      } else if let dto = decodeDTOManually(doc.data()) {
        items.append(dto)
      }
    }
    
    print("Kemuel \(items.count) \(dayKey)")
    return GlobalFeedPage(items: items, lastSnapshot: snap.documents.last)
  }
  
  private static func decodeDTOManually(_ d: [String: Any]) -> MemoryDTO? {
    guard let id = d["id"] as? String,
          let userID = d["userID"] as? String,
          let username = d["username"] as? String,
          let mood = d["mood"] as? String,
          let journalText = d["journalText"] as? String,
          let likes = d["likes"] as? Int,
          let isPublic = d["isPublic"] as? Bool,
          let dateTS = d["date"] as? Timestamp
    else { return nil }
    let profilePhotoURL = d["remoteProfilePhotoURL"] as? String
    print("Kemuel photo \(profilePhotoURL)")
    let isPremium = d["isPremium"] as? Bool ?? false
    let date = dateTS.dateValue()
    return MemoryDTO(
      id: id,
      username: username,
      userID: userID,
      date: date,
      mood: mood,
      journalText: journalText,
      likes: likes,
      remoteImagePaths: d["remoteImagePaths"] as? [String] ?? [],
      videoRemoteURL: d["videoRemoteURL"] as? String,
      linkURL: d["linkURL"] as? String,
      remoteProfilePhotoURL: profilePhotoURL,
      isPublic: isPublic,
      isPremium: isPremium,
      createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
      updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
      authorTZ: (d["authorTZ"] as? String) ?? TimeZone.current.identifier,
      dayKey: (d["dayKeyLocal"] as? String) ?? date.formattedDayKeyLocal()
    )
  }
}

// MARK: - Test

extension GlobalFeedService {
  static func generateTestPage(
    for day: Date,
    count: Int,
    startIndex: Int = 0
  ) -> GlobalFeedPage {
    var items: [MemoryDTO] = []
    items.reserveCapacity(count)
    
    // Use your real enum if available; otherwise fall back to strings
    let moodStrings: [String] = Mood.allCases.map(\.rawValue)
    
    let cal = Calendar(identifier: .gregorian)
    let tzID = TimeZone.current.identifier
    let dayKey = day.formattedDayKeyLocal()
    
    for i in 0..<count {
      let idx = startIndex + i
      let created = cal.date(byAdding: .minute, value: -idx, to: Date())!
      
      let hasImage = idx % 3 == 0
      let hasLink  = idx % 7 == 0
      
      items.append(
        MemoryDTO(
          id: UUID().uuidString,
          username: "user\(idx)",
          userID: "test-\(idx)",
          date: day,
          mood: moodStrings[idx % moodStrings.count],
          journalText: idx % 4 == 0 ? "Test post #\(idx) for \(day.formatted())" : "",
          likes: 10,
          remoteImagePaths: hasImage ? ["https://picsum.photos/seed/\(idx)/800/600"] : [],
          videoRemoteURL: nil,
          linkURL: hasLink ? "https://example.com/\(idx)" : nil,
          isPublic: true,
          isPremium: Bool.random(),
          createdAt: created,
          updatedAt: created,
          authorTZ: tzID,
          dayKey: dayKey
        )
      )
    }
    
    return GlobalFeedPage(items: items, lastSnapshot: nil)
  }
}
