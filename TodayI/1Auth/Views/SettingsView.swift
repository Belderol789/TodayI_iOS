import SwiftUI
import PhotosUI
import UIKit
import LocalAuthentication
import UserNotifications

struct SettingsView: View {
  @EnvironmentObject private var auth: AuthStore
  @EnvironmentObject private var entitlements: EntitlementStore
  @Environment(\.swiftDataManager) private var swiftManager
  @Environment(\.dismiss) private var dismiss
  
  @AppStorage("requireFaceID") private var requireFaceID = false
  @State private var biometricsAvailable: Bool = false

  // Daily reminder
  @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = false
  @AppStorage("dailyReminderHour") private var dailyReminderHour = 20
  @AppStorage("dailyReminderMinute") private var dailyReminderMinute = 0
  @State private var reminderDate: Date = Calendar.current.date(
    from: DateComponents(hour: 20, minute: 0)) ?? Date()
  @State private var notificationsAuthorized = false

  @State private var draftUsername: String = ""
  @State private var isSaving = false
  @State private var isLoggingOut = false
  @State private var isDeletingAccount = false
  @State private var showDeleteConfirm = false
  @State private var deleteError: String?
  @State private var sampleYearOn = false
  @State private var showSignIn = false
  
  // Photo picking + preview
  @State private var showPhotoPicker = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var profileUIImage: UIImage?          // raw image for upload
  @State private var profileImage: Image?              // SwiftUI image for preview
  @State private var photoDirty = false                // has the user picked a new photo this session?

  // If you already have a remote photo URL on the user doc and want to show it:
  // You can pass it into this view or fetch from SwiftData. For now we only preview local picks.
  
  private var usernameChanged: Bool {
    draftUsername.trimmingCharacters(in: .whitespacesAndNewlines) != (auth.username ?? "")
  }
  
  private var hasUnsavedChanges: Bool {
    usernameChanged || photoDirty
  }
  
  var authUserPhotoURL: String? {
    auth.photoURL
  }
  
  var body: some View {
    List {
      // MARK: - Profile Section
      Section {
        HStack(spacing: 16) {
          profilePhotoTile
          
          VStack(alignment: .leading, spacing: 4) {
            Text("Username")
              .font(.caption)
              .foregroundStyle(.secondary)
            
            TextField("Enter username", text: $draftUsername)
              .textInputAutocapitalization(.none)
              .disableAutocorrection(true)
          }
        }
        .padding(.vertical, 4)
      } header: {
        Text("Profile")
      }
      
      // MARK: - Account Section
      // Guests reach Settings too: Face ID, the reminder and the username are about the
      // journal, not the account, and sign-in is only ever required for posting Global
      // and buying Premium. Home used to send guests to the sign-in screen instead.
      Section {
        if auth.isGuest {
          Button {
            showSignIn = true
          } label: {
            Label("Sign In", systemImage: "person.crop.circle.badge.plus")
          }
        } else {
          HStack {
            Text("Signed in")
            Spacer()
            Text(auth.email ?? "Registered")
              .foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("Account")
      } footer: {
        if auth.isGuest {
          Text("You're journaling as a guest. Your entries stay on this iPhone. Sign in to post to the World feed or to get Premium's cloud backup.")
        }
      }
      
      // MARK: - Notifications
      if notificationsAuthorized {
        Section {
          Toggle("Daily Reminder", isOn: $dailyReminderEnabled)
            .onChange(of: dailyReminderEnabled) { _, enabled in
              Task { await applyReminderChange(enabled: enabled) }
            }

          if dailyReminderEnabled {
            DatePicker("Reminder Time",
                       selection: $reminderDate,
                       displayedComponents: .hourAndMinute)
              .onChange(of: reminderDate) { _, date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                dailyReminderHour = comps.hour ?? 20
                dailyReminderMinute = comps.minute ?? 0
                Task { await applyReminderChange(enabled: true) }
              }
          }
        } header: {
          Text("Notifications")
        } footer: {
          Text(dailyReminderEnabled
               ? "You'll get a daily nudge to log how you're feeling."
               : "Get a daily nudge to log how you're feeling.")
        }
      }

      // MARK: - Security
      if biometricsAvailable {
        Section {
          Toggle("Require Face ID", isOn: $requireFaceID)
        } header: {
          Text("Security")
        } footer: {
          Text("When enabled, Face ID is required to view your calendar.")
        }
      }

      // MARK: - Debug (only in non-release builds)
      #if DEBUG
      Section {
        // Drives the DEBUG-only override, not `isPremium` itself — that is derived
        // from StoreKit now and has no setter. A real subscription keeps Premium on
        // regardless of this switch.
        Toggle("Force Premium", isOn: Binding(
          get: { entitlements.devForcePremium },
          set: { entitlements.devForcePremium = $0 }
        ))

        // The check-in otherwise only arrives at 8pm local, and the server push
        // additionally needs a functions deploy — neither is testable on demand.
        // Also the quickest route to the permission prompt: APNs never registers
        // until notifications are authorised, which leaves the topic queue full.
        Button("Send check-in notification (5s)") {
          Task {
            await NotificationManager.shared.debugSendCheckInPreview()
            dismiss()   // so the app can be backgrounded to see the banner
          }
        }

        // The streak states depend on which days already have entries, so they
        // can't be reached by tapping around on a single day.
        Button("Seed 7-day streak (today logged)") {
          swiftManager?.debugSeedStreak(count: 7, includingToday: true)
        }
        Button("Seed 3-day streak (today still open)") {
          swiftManager?.debugSeedStreak(count: 3, includingToday: false)
        }
        Button("Clear local mood days", role: .destructive) {
          swiftManager?.debugClearMoodDays()
        }

        // For App Store screenshots: a filled calendar, a streak, and a memory on most
        // days. Local only — see `debugSeedSampleYear`.
        Toggle("Sample year (screenshots)", isOn: Binding(
          get: { sampleYearOn },
          set: { on in
            guard let manager = swiftManager else { return }
            if on, let uid = auth.userID {
              manager.debugSeedSampleYear(userID: uid,
                                          username: auth.username ?? "guest",
                                          isPremium: entitlements.isPremium)
            } else {
              manager.debugClearSampleYear()
            }
            sampleYearOn = manager.hasSampleYear
          }
        ))
        .onAppear { sampleYearOn = swiftManager?.hasSampleYear ?? false }
      } header: {
        Text("Developer")
      } footer: {
        Text("""
        \(entitlements.isPremium
          ? "Premium is ON. Turn this off to see the free-tier gates."
          : "Premium is OFF — free-tier gates are active.")

        Seeding writes mood days locally only — no posts, nothing uploaded. Existing         days are never overwritten. Clearing removes the local cache; Calendar         pull-to-refresh restores it from Firestore.

        Sample year fills January 1 to today with local memories for screenshots. They are \
        never uploaded, and turning it off removes only what it added.

        Push needs notification permission before APNs will register. If the launch log \
        shows "Queued …" with no "APNs ready", send a check-in and allow the prompt.
        """)
      }
      #endif

      // MARK: - Account actions
      // A guest has no account to sign out of or delete; their entries live on the device.
      if !auth.isGuest {
      Section {
        Button(role: .destructive) {
          isLoggingOut = true
          Task {
            await auth.signOutToGuest()
            isLoggingOut = false
            dismiss()
          }
        } label: {
          if isLoggingOut {
            ProgressView().tint(.red)
          } else {
            Text("Log Out")
          }
        }
        .disabled(isLoggingOut || isDeletingAccount)

        Button(role: .destructive) {
          showDeleteConfirm = true
        } label: {
          if isDeletingAccount {
            ProgressView().tint(.red)
          } else {
            Text("Delete Account")
          }
        }
        .disabled(isDeletingAccount || isLoggingOut)
      } footer: {
        if let deleteError {
          Text(deleteError)
            .foregroundStyle(.red)
            .font(.caption)
        }
      }
      }
    }
    .sheet(isPresented: $showSignIn) {
      // Closes itself once sign-in succeeds; Settings then shows the signed-in account.
      AuthView()
    }
    .alert("Delete Account?", isPresented: $showDeleteConfirm) {
      Button("Delete", role: .destructive) {
        Task { await performDeleteAccount() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(auth.isLinkedToApple
           ? "This permanently deletes your account, all memories, and cannot be undone. Apple will ask you to confirm once more."
           : "This permanently deletes your account, all memories, and cannot be undone.")
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await saveChangesAndDismiss() }
        } label: {
          if isSaving { ProgressView() } else { Text("Save").bold() }
        }
        .disabled(!hasUnsavedChanges || isSaving)
      }
    }
    .onAppear {
      draftUsername = auth.username ?? ""
      let ctx = LAContext()
      biometricsAvailable = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
      reminderDate = Calendar.current.date(
        from: DateComponents(hour: dailyReminderHour, minute: dailyReminderMinute)) ?? reminderDate
      Task {
        let status = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
          notificationsAuthorized = status.authorizationStatus == .authorized
            || status.authorizationStatus == .provisional
        }
      }
    }
    .photosPicker(isPresented: $showPhotoPicker,
                  selection: $selectedPhotoItem,
                  matching: .images)
    .onChange(of: selectedPhotoItem) { _, newItem in
      guard let newItem else { return }
      Task {
        if let data = try? await newItem.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
          await MainActor.run {
            profileUIImage = uiImage
            profileImage = Image(uiImage: uiImage)
            photoDirty = true
          }
        }
      }
    }
  }
}

// MARK: - Profile Photo UI
private extension SettingsView {
  @ViewBuilder
  var profilePhotoTile: some View {
    let tile = ZStack {
      if let image = profileImage {
        image
          .resizable()
          .scaledToFill()
          .frame(width: 64, height: 64)
          .clipShape(Circle())
      } else if let urlString = authUserPhotoURL,
                let url = URL(string: urlString) {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let img):
            img.resizable()
              .scaledToFill()
              .frame(width: 64, height: 64)
              .clipShape(Circle())
          case .failure(_):
            placeholderCircle
          case .empty:
            ProgressView()
              .frame(width: 64, height: 64)
          @unknown default:
            placeholderCircle
          }
        }
      } else {
        placeholderCircle
      }
    }
    
    if entitlements.isPremium {
      Button {
        showPhotoPicker = true
      } label: {
        tile
      }
      .buttonStyle(.plain)
      .overlay(alignment: .bottomTrailing) {
        // small premium checkmark hint
        Image(systemName: "star.fill")
          .font(.system(size: 10))
          .foregroundColor(.yellow)
          .background(
            Circle().fill(.black.opacity(0.7)).frame(width: 16, height: 16)
          )
          .offset(x: 2, y: 2)
      }
    } else {
      tile
        .opacity(0.6)
        .overlay {
          // lock overlay for non-premium
          RoundedRectangle(cornerRadius: 40, style: .continuous)
            .fill(.black.opacity(0.25))
          VStack(spacing: 6) {
            Image(systemName: "lock.fill")
              .foregroundColor(.white)
              .font(.system(size: 14, weight: .bold))
            Text("Premium")
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(.white)
          }
        }
        .accessibilityLabel("Profile photo (premium required to change)")
    }
  }
  
  private var placeholderCircle: some View {
    Circle()
      .fill(Color(.systemGray4))
      .frame(width: 64, height: 64)
      .overlay(
        Image(systemName: "camera.fill")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(.white)
      )
  }
  
}

// MARK: - Save Logic
private extension SettingsView {
  func performDeleteAccount() async {
    isDeletingAccount = true
    deleteError = nil
    do {
      try await auth.deleteAccount()
      isDeletingAccount = false
      dismiss()
    } catch AuthStore.DeleteError.cancelled {
      // Backed out of the Apple re-confirmation: nothing happened, nothing to report.
      isDeletingAccount = false
    } catch {
      isDeletingAccount = false
      deleteError = error.localizedDescription
    }
  }

  func applyReminderChange(enabled: Bool) async {
    if enabled {
      try? await NotificationManager.shared.rescheduleDaily(
        id: "daily-reminder",
        hour: dailyReminderHour,
        minute: dailyReminderMinute,
        title: "How are you feeling today?",
        body: "Take a moment to log your mood in TodayI."
      )
    } else {
      NotificationManager.shared.cancel(id: "daily-reminder")
    }
  }

  func saveChangesAndDismiss() async {
    guard let uid = auth.userID else { return }
    if !hasUnsavedChanges { dismiss(); return }
    
    isSaving = true
    defer { isSaving = false }
    
    // 1) Upload photo if user picked a new one AND is premium
    if photoDirty, entitlements.isPremium, let img = profileUIImage {
      do {
        let url = try await FirebaseStorageManager.uploadProfilePhoto(img, userID: uid)
        await auth.updateProfilePhoto(url: url.absoluteString, localImage: img) // updates Firestore + SwiftData
        photoDirty = false
      } catch {
        print("Profile photo upload failed:", error)
        // (Optional) Present an error UI here and return early if you don't want to continue saving username.
      }
    }
    
    // 2) Update username if changed
    if usernameChanged {
      let trimmed = draftUsername.trimmingCharacters(in: .whitespacesAndNewlines)
      await auth.updateUsername(trimmed)
    }
    
    // 3) Auto-dismiss
    dismiss()
  }
}
