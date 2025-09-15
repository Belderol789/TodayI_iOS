import SwiftUI
import PhotosUI
import AVKit   // ⟵ add this

struct CreateMemoryView: View {
  @EnvironmentObject private var entitlements: EntitlementStore
  @Environment(\.swiftDataManager) private var swiftManager
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.dismiss) private var dismiss
  @StateObject private var vm = CreateMemoryViewModel()
  
  @State private var showPreview = false
  @State private var postedMemory: MemoryModel? = nil
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          header
          if let indicator = vm.attachmentIndicatorText {
            Text(indicator)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal)
          }
          videoSection
          mediaSection
          linkSection
          journalSection
          counterSection
          quickActions
        }
        .padding(.top, 10)
      }
      .navigationTitle("Create")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) { postButton }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(entitlements.isPremium ? "Set Free" : "Set Premium") {
            entitlements.isPremium.toggle()
          }
        }
      }
      .onAppear {
        vm.isPremium = entitlements.isPremium
        vm.onPost = { payload in
          guard let swiftManager, let uid = auth.userID else { return }
          let username = auth.username ?? "Me"
          
          do {
            if let model = try swiftManager.savePostPayload(payload,
                                                            userID: uid,
                                                            username: username) as MemoryModel? {
              postedMemory = model          // keep a reference so the sheet can bind to it
              showPreview = true            // present modal
              vm.clearAll()                 // reset composer
            }
          } catch {
            print("Save failed: \(error)")
            // surface an error toast if you like
          }
        }
      }
      .onChange(of: entitlements.isPremium) { _, new in
        vm.isPremium = new
      }
      // Pickers
      .photosPicker(isPresented: $vm.presentSinglePicker,
                    selection: $vm.singleItem,
                    matching: .images)
      .onChange(of: vm.singleItem) { _, _ in
        Task { await vm.handleSingleSelectionChange() }
      }
      .photosPicker(isPresented: $vm.presentMultiPicker,
                    selection: $vm.galleryItems,
                    maxSelectionCount: entitlements.isPremium ? 12 : 1,
                    matching: .images)
      .onChange(of: vm.galleryItems) { _, _ in
        Task { await vm.handleGallerySelectionChange() }
      }
      .photosPicker(
        isPresented: $vm.presentVideoPicker,
        selection: $vm.videoItem,
        matching: .videos
      )
      .onChange(of: vm.videoItem) { _, _ in
        Task { await vm.handleVideoSelectionChange() }
      }
      .alert("Add a link", isPresented: $vm.showLinkPrompt) {
        TextField("https://example.com", text: $vm.tempLinkInput)
        Button("Cancel", role: .cancel) { vm.tempLinkInput = "" }
        Button("Add") {
          let trimmed = vm.tempLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty {
            vm.linkString = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
          }
          vm.tempLinkInput = ""
        }
      } message: {
        Text("Paste a website link to preview it.")
      }
      .sheet(isPresented: $showPreview) {
        if let mem = postedMemory {
          // Wrap in a NavigationStack to get a close button
          NavigationStack {
            ScrollView {
              MemoryRow(memory: mem, isPremium: entitlements.isPremium)
                .environmentObject(auth) // inherits from parent, usually not needed, but safe
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showPreview = false }
              }
            }
          }
        }
      }
    }
  }
}

// MARK: - Sections
extension CreateMemoryView {
  
  // MARK: - Header (Today I feel + mood dropdown)
  private var header: some View {
    HStack(spacing: 4) {
      Text("TodayI feel")
        .font(.headline)
        .frame(minWidth: 100, alignment: .leading)
      
      // Mood dropdown
      Menu {
        ForEach(Mood.allCases) { mood in
          Button {
            vm.choose(mood: mood)
          } label: {
            HStack(spacing: 8) {
              MoodIcon(mood: mood, size: 20)
              Text(mood.rawValue)
                .font(.headline.bold())
                .foregroundStyle(mood.adaptiveColor)
            }
          }
        }
        
        if vm.selectedMood != nil {
          Divider()
          Button(role: .destructive) {
            vm.selectedMood = nil
          } label: {
            Label("Clear", systemImage: "xmark")
          }
        }
      } label: {
        Group {
          if let mood = vm.selectedMood {
            HStack(spacing: 4) {
              if entitlements.isPremium {
                Text(mood.rawValue)
                  .font(.headline.bold())
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(Capsule().fill(mood.adaptiveColor))
                  .foregroundStyle(Color(.systemBackground))
                  .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
                MoodIcon(mood: mood, size: 24)
              } else {
                Text(mood.rawValue)
                  .font(.headline.bold())
                  .foregroundStyle(mood.adaptiveColor)
                MoodIcon(mood: mood, size: 24)
              }
            }
          } else {
            HStack(spacing: 8) {
              Text("Select mood")
                .font(.subheadline)
                .foregroundStyle(.secondary)
              Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
          }
        }
        // 🔑 Fix width so the menu label doesn’t shrink
        .frame(minWidth: 160, alignment: .leading)
      }
      
      Spacer()
      
      // Today’s date using the extension
      Text(Date().formatted("MMM d, yyyy"))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal)
    .padding(.top, 4)
  }
  
  var mediaSection: some View {
    Group {
      if !vm.pickedImages.isEmpty {
        MediaSection(
          images: vm.pickedImages,
          onRemove: { id in vm.removeImage(id) }
        )
        .padding(.horizontal)
      }
    }
  }
  
  private var journalSection: some View {
    PlaceholderTextEditor(
      text: $vm.text,
      placeholder: "Write your thoughts for today…",
      minHeight: 160,
      maxHeight: 220
    )
    .padding(.horizontal)
  }
  
  private var videoSection: some View {
    Group {
      if let player = vm.videoPlayer {
        ZStack {
          VideoPlayer(player: player)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear { player.play() }
            .onDisappear { player.pause() }
          
          // Put the close button on the *top-left* to avoid AirPlay/PiP controls
          VStack {
            HStack {
              Button {
                vm.clearVideo()
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.title3)
                  .symbolRenderingMode(.hierarchical)
                  .foregroundStyle(.primary)
                  .padding(8)
                  .background(.thinMaterial, in: Circle())
                  .contentShape(Circle())
              }
              .buttonStyle(.plain)
              .padding(.leading, 8)
              .padding(.top, 8)
              
              Spacer()
            }
            Spacer()
          }
          .allowsHitTesting(true)
        }
        .padding(.horizontal)
      }
    }
  }
  
  private var linkSection: some View {
    Group {
      if let linkString = vm.linkString,
         let url = URL(string: linkString) {
        ZStack(alignment: .topTrailing) {
          // 👇 Option 1: open in Safari by default
          Link(destination: url) {
            LinkPreviewView(url: url)
              .frame(height: 120)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .padding(.horizontal)
          }
          .buttonStyle(.plain) // so the preview card isn’t dimmed
          
          // Remove button
          Button {
            vm.clearLink()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.title3)
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.primary)
              .padding(6)
              .background(.thinMaterial, in: Circle())
          }
          .buttonStyle(.plain)
          .padding(.trailing, 24)
          .padding(.top, 8)
        }
      }
    }
  }
  
  private var counterSection: some View {
    HStack {
      PrivacyBadge(isPublic: $vm.isPublic)
      Spacer()
      if entitlements.isPremium {
        PremiumPill(isPremium: true)
      } else {
        Text("\(vm.remaining) left")
          .font(.caption)
          .foregroundStyle(vm.remaining < 20 ? .orange : .secondary)
      }
    }
    .padding(.horizontal)
  }
  
  private var quickActions: some View {
    HStack(spacing: 12) {
      QuickActionButton(
        title: "Photo", systemImage: "photo",
        action: { vm.tapPhoto() },
        isEnabled: true,
        color: vm.selectedMood?.adaptiveColor
      )
      QuickActionButton(
        title: "Video", systemImage: "video",
        action: { vm.tapVideo() },
        isEnabled: entitlements.isPremium,
        color: vm.selectedMood?.adaptiveColor
      )
      QuickActionButton(
        title: "Gallery", systemImage: "photo.on.rectangle",
        action: { vm.tapGallery() },
        isEnabled: entitlements.isPremium,
        color: vm.selectedMood?.adaptiveColor
      )
      QuickActionButton(
        title: "Link", systemImage: "link",
        action: {
          vm.tapLink()
        },
        isEnabled: true,
        color: vm.selectedMood?.adaptiveColor
      )
    }
    .padding(.horizontal)
    .padding(.bottom, 120)
  }
  
  private var postButton: some View {
    HStack {
      Spacer(minLength: 0)
      Button {
        vm.pressPost()
      } label: {
        Text("Post")
          .font(.headline.bold())
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
          .background(
            Capsule()
              .fill((vm.selectedMood?.adaptiveColor ?? .secondary)
                .opacity(vm.canPost ? 1.0 : 0.4))
          )
          .foregroundStyle(Color(.systemBackground))
          .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
      }
      .disabled(!vm.canPost)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 12)
    .background(.regularMaterial)
  }
}
