import SwiftUI
import PhotosUI
import UIKit   // for UIImage

struct SettingsView: View {
  @EnvironmentObject private var auth: AuthStore
  @EnvironmentObject private var entitlements: EntitlementStore
  @Environment(\.dismiss) private var dismiss
  
  @State private var draftUsername: String = ""
  @State private var isSaving = false
  @State private var isLoggingOut = false
  
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
      Section("Account") {
        HStack {
          Text("Status")
          Spacer()
          Text(auth.isGuest ? "Guest" : "Registered")
            .foregroundStyle(auth.isGuest ? .orange : .green)
        }
      }
      
      // MARK: - Debug (only in non-release builds)
      #if DEBUG
      Section("Developer") {
        Toggle("Premium", isOn: $entitlements.isPremium)
      }
      #endif

      // MARK: - Logout
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
      }
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
