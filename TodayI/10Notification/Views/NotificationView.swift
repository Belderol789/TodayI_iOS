import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct NotificationView: View {
  @EnvironmentObject private var auth: AuthStore
  
  // Live state
  @State private var items: [AppNotificationDTO] = []
  @State private var unreadCount: Int = 0
  @State private var isRefreshing = false
  @State private var showSetting = false
  @State private var filterUnreadOnly = true
  
  // For navigation
  @State private var selectedMemory: MemoryModel? = nil
  @State private var showDetail = false
  
  // Listener
  @State private var listener: ListenerRegistration?
  @State private var isFetchingMemory = false
  
  var body: some View {
    NavigationStack {
      Group {
        if auth.isGuest {
          AuthRequiredView { showSetting = true }
        } else {
          VStack(spacing: 0) {
            Picker("Filter", selection: $filterUnreadOnly) {
              Text("All").tag(false)
              Text("Unread").tag(true)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            
            content
          }
        }
      }
      .navigationTitle("Notifications")
      .toolbar {
        if unreadCount > 0, !auth.isGuest, let uid = Auth.auth().currentUser?.uid {
          Button("Mark all read") {
            NotificationManager.shared.markNotificationsRead(uid: uid, ids: items.map(\.id))
          }
        }
      }
      .onAppear { refreshAndListen() }
      .onDisappear { stopListening() }
      .onChange(of: filterUnreadOnly) { _, _ in refreshAndListen() }
      .sheet(isPresented: $showSetting) {
        NavigationStack { AuthView() }
      }
      // 👇 Navigation destination to comment thread
      .navigationDestination(isPresented: $showDetail) {
        if let memory = selectedMemory {
          CommentThreadView(memory: memory)
        }
      }
    }
    .overlay {
      if isFetchingMemory {
        ZStack {
          Color.black.opacity(0.2).ignoresSafeArea()
          ProgressView("Loading post…")
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: isFetchingMemory)
  }
  
  // MARK: - Content
  private var content: some View {
    Group {
      if items.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "bell")
            .font(.system(size: 36, weight: .regular))
            .foregroundColor(.secondary)
          Text("No notifications yet")
            .font(.headline)
          Text("You’ll see likes and comment milestones here.")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(items) { n in
            NotificationRow(notification: n) {
              if let uid = Auth.auth().currentUser?.uid {
                NotificationManager.shared.markNotificationRead(uid: uid, id: n.id)
              }
              Task { await fetchAndShowMemory(memoryId: n.postId) }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 4)
          }
        }
        .listStyle(.plain)
        .refreshable { await refreshOnce() }
      }
    }
  }
  
  // MARK: - Firestore fetch
  private func fetchAndShowMemory(memoryId: String) async {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    let db = Firestore.firestore()
    await MainActor.run { isFetchingMemory = true }
    
    do {
      let memRef = db.collection("users").document(uid)
        .collection("memories").document(memoryId)
      let snap = try await memRef.getDocument()
      guard let data = snap.data() else {
        print("⚠️ No memory found for id:", memoryId)
        await MainActor.run { isFetchingMemory = false }
        return
      }
      
      let memory = MemoryModel(
        id: data["id"] as? String ?? memoryId,
        userID: data["userID"] as? String ?? "",
        username: data["username"] as? String ?? "",
        remoteProfilePhotoURL: data["remoteProfilePhotoURL"] as? String,
        localProfilePhotoPath: nil,
        date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
        mood: Mood(rawValue: data["mood"] as? String ?? "neutral") ?? .neutral,
        journalText: data["journalText"] as? String ?? "",
        likes: data["likes"] as? Int ?? 0,
        remoteImagePaths: data["remoteImagePaths"] as? [String] ?? [],
        videoRemoteURL: data["videoRemoteURL"] as? String,
        linkURL: data["linkURL"] as? String,
        isPublic: data["isPublic"] as? Bool ?? false,
        isPremium: data["isPremium"] as? Bool ?? false,
        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
      )
      
      await MainActor.run {
        self.selectedMemory = memory
        self.showDetail = true
        self.isFetchingMemory = false
      }
    } catch {
      print("❌ Failed to fetch memory:", error)
      await MainActor.run { isFetchingMemory = false }
    }
  }
  
  // MARK: - Inbox wiring
  private func refreshAndListen() {
    Task {
      await refreshOnce(forceReload: true)
      startNotificationListening()
    }
  }
  
  private func startNotificationListening() {
    guard !auth.isGuest, let uid = Auth.auth().currentUser?.uid else { return }
    stopListening()
    listener = NotificationManager.shared.listenUserInbox(
      uid: uid,
      unreadOnly: filterUnreadOnly
    ) { newItems, unread in
      self.items = newItems
      self.unreadCount = unread
    }
  }
  
  private func stopListening() {
    listener?.remove()
    listener = nil
    items = []
    unreadCount = 0
  }
  
  private func refreshOnce(forceReload: Bool = false) async {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    if forceReload { stopListening() }
    isRefreshing = true
    do {
      let fresh = try await NotificationManager.shared.fetchUserInboxOnce(
        uid: uid,
        limit: 100,
        unreadOnly: filterUnreadOnly
      )
      await MainActor.run {
        self.items = fresh
        self.unreadCount = fresh.filter { !$0.read }.count
      }
    } catch {
      print("Inbox refresh failed:", error)
    }
    isRefreshing = false
  }
}
