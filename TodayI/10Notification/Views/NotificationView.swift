import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

struct NotificationView: View {
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.modelContext) private var context
  @Binding var tabSelection: AppTab
  /// Set when a notification is tapped; drives the push to that post's thread.
  @State private var openedMemory: MemoryModel?

  // Live state — `allItems` is the listener's output; the filter is applied locally
  // so flipping the segmented control costs nothing.
  @State private var allItems: [AppNotificationDTO] = []
  @State private var isRefreshing = false
  @State private var showSetting = false
  /// Defaults to All. Starting on Unread showed an empty screen to anyone who had
  /// already read their notifications, which reads as "notifications are broken".
  @State private var filterUnreadOnly = false

  private var items: [AppNotificationDTO] {
    filterUnreadOnly ? allItems.filter { !$0.read } : allItems
  }
  private var unreadCount: Int { allItems.filter { !$0.read }.count }

  // Listener
  @State private var listener: ListenerRegistration?

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
        ToolbarItem(placement: .topBarTrailing) {
          if unreadCount > 0, !auth.isGuest, let uid = Auth.auth().currentUser?.uid {
            Button("Mark all read") {
              NotificationManager.shared.markNotificationsRead(uid: uid, ids: items.map(\.id))
            }
          }
        }
      }
      .onAppear {
        startNotificationListening()
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
      }
      .onDisappear { stopListening() }
      .onChange(of: unreadCount) { _, count in
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
      }
      .navigationDestination(item: $openedMemory) { memory in
        CommentThreadView(memory: memory)
      }
      .sheet(isPresented: $showSetting) {
        NavigationStack { AuthView() }
      }
    }
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
          Text("You'll see likes and comment milestones here.")
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
              Task { await open(postID: n.postId) }
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

  // MARK: - Inbox wiring

  /// Attaches the snapshot listener, which delivers the current inbox as its first
  /// callback. There used to be a one-shot 100-document fetch here as well, so every
  /// appearance read the same data twice.
  private func startNotificationListening() {
    guard !auth.isGuest, let uid = Auth.auth().currentUser?.uid else { return }
    guard listener == nil else { return }
    // Always listens to the full inbox; `filterUnreadOnly` filters in memory, so the
    // segmented control no longer tears the query down and rebuilds it.
    listener = NotificationManager.shared.listenUserInbox(
      uid: uid,
      unreadOnly: false
    ) { newItems, _ in
      self.allItems = newItems
      Task { try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount) }
    }
  }

  private func stopListening() {
    listener?.remove()
    listener = nil
    // `allItems` is deliberately kept: returning to the tab shows the last inbox
    // immediately while the listener re-attaches.
  }

  /// Opens the post a milestone is about, instead of dumping the user in the World
  /// feed — which couldn't show the post at all when it was private.
  /// Milestones are always about the signed-in user's own memory, so it lives at
  /// `users/{uid}/memories/{postId}`. Local first; one read only if it isn't cached.
  @MainActor
  private func open(postID: String) async {
    guard !postID.isEmpty, let uid = Auth.auth().currentUser?.uid else {
      tabSelection = .global
      return
    }

    var fetch = FetchDescriptor<MemoryModel>(predicate: #Predicate { $0.id == postID })
    fetch.fetchLimit = 1
    if let local = try? context.fetch(fetch).first {
      openedMemory = local
      return
    }

    if let dto = try? await MemoryService.fetchMemory(userID: uid, memoryID: postID),
       let model = try? MemoryModel.upsert(from: dto, in: context) {
      try? context.save()
      openedMemory = model
      return
    }

    // Post is gone (deleted, or not ours) — fall back to the old behaviour.
    tabSelection = .global
  }

  private func refreshOnce() async {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    isRefreshing = true
    do {
      let fresh = try await NotificationManager.shared.fetchUserInboxOnce(
        uid: uid,
        limit: 100,
        unreadOnly: false
      )
      await MainActor.run { self.allItems = fresh }
    } catch {
      print("Inbox refresh failed:", error)
    }
    isRefreshing = false
  }
}
