import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

struct NotificationView: View {
  @EnvironmentObject private var auth: AuthStore
  @Binding var tabSelection: AppTab

  // Live state
  @State private var items: [AppNotificationDTO] = []
  @State private var unreadCount: Int = 0
  @State private var isRefreshing = false
  @State private var showSetting = false
  @State private var filterUnreadOnly = true

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
        if unreadCount > 0, !auth.isGuest, let uid = Auth.auth().currentUser?.uid {
          Button("Mark all read") {
            NotificationManager.shared.markNotificationsRead(uid: uid, ids: items.map(\.id))
          }
        }
      }
      .onAppear {
        refreshAndListen()
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
      }
      .onDisappear { stopListening() }
      .onChange(of: filterUnreadOnly) { _, _ in refreshAndListen() }
      .onChange(of: unreadCount) { _, count in
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
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
              tabSelection = .global
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
      Task { try? await UNUserNotificationCenter.current().setBadgeCount(unread) }
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
