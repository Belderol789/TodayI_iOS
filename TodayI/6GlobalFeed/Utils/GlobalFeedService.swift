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
    let dayKey = day.dayKeyUTC
    
    var q: Query = db.collectionGroup("memories")
      .whereField("isPublic", isEqualTo: true)
      .whereField("dayKeyUTC", isEqualTo: dayKey)
      .order(by: "createdAt", descending: true)
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
    
    return GlobalFeedPage(items: items, lastSnapshot: snap.documents.last)
  }
  
  private static func decodeDTOManually(_ d: [String: Any]) -> MemoryDTO? {
    guard let id = d["id"] as? String,
          let userID = d["userID"] as? String,
          let username = d["username"] as? String,
          let mood = d["mood"] as? String,
          let journalText = d["journalText"] as? String,
          let isPublic = d["isPublic"] as? Bool,
          let dateTS = d["date"] as? Timestamp
    else { return nil }
    
    let date = dateTS.dateValue()
    return MemoryDTO(
      id: id,
      username: username,
      userID: userID,
      date: date,
      mood: mood,
      journalText: journalText,
      remoteImagePaths: d["remoteImagePaths"] as? [String] ?? [],
      videoRemoteURL: d["videoRemoteURL"] as? String,
      linkURL: d["linkURL"] as? String,
      isPublic: isPublic,
      createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
      updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
      authorTZ: (d["authorTZ"] as? String) ?? TimeZone.current.identifier,
      dayKeyLocal: (d["dayKeyLocal"] as? String) ?? date.dayKeyLocal(in: .current),
      dayKeyUTC: d["dayKeyUTC"] as? String
    )
  }
}

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
    let dayKeyLocal = day.dayKeyLocal(in: .current)
    let dayKeyUTC   = day.dayKeyUTC
    
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
          remoteImagePaths: hasImage ? ["https://picsum.photos/seed/\(idx)/800/600"] : [],
          videoRemoteURL: nil,
          linkURL: hasLink ? "https://example.com/\(idx)" : nil,
          isPublic: true,
          createdAt: created,
          updatedAt: created,
          authorTZ: tzID,
          dayKeyLocal: dayKeyLocal,
          dayKeyUTC: dayKeyUTC
        )
      )
    }
    
    return GlobalFeedPage(items: items, lastSnapshot: nil)
  }
}
