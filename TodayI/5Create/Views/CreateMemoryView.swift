import SwiftUI
import PhotosUI
import AVKit

struct CreateMemoryView: View {
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.swiftDataManager) private var swiftManager
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.colorScheme) private var scheme
  @StateObject private var vm = CreateMemoryViewModel()

  private var moodGradient: LinearGradient {
    LinearGradient(colors: Mood.allCases.map(\.adaptiveColor), startPoint: .leading, endPoint: .trailing)
  }

  @State private var showPreview = false
  @State private var showPremium = false
  @State private var showAuth = false
  @State private var postedMemory: MemoryModel? = nil

  var body: some View {
    NavigationStack {
      ScrollView {

        VStack(spacing: 0) {
          moodPicker
            .padding(.top, 8)
            .padding(.bottom, 20)

          moodHeadline
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

          contentCard
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

          privacyRow
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
      .navigationTitle("Create")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          postToolbarButton
        }
      }
      .onAppear(perform: configureViewModel)
      .onChange(of: entitlements.isPremium) { _, new in vm.isPremium = new }
      .onChange(of: auth.isRegisteredUser) { _, isRegistered in
        if isRegistered { vm.isPublic = true }
      }
      .modifier(MediaPickers(vm: vm, entitlements: entitlements))
      .modifier(LinkAlert(vm: vm))
      .sheet(isPresented: $showPreview) { previewSheet }
      .sheet(isPresented: $showAuth) {
        NavigationStack { AuthView() }
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
          .presentationCornerRadius(20)
      }
      .sheet(isPresented: $showPremium) {
        PremiumView()
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
          .interactiveDismissDisabled(false)
          .presentationCornerRadius(20)
          .preferredColorScheme(.dark)
      }
    }
  }

  // MARK: - Mood picker (fixed 2-row grid — no scroll bias)

  private var moodPicker: some View {
    let all = Mood.allCases
    let topRow = Array(all.prefix(4))
    let bottomRow = Array(all.suffix(3))
    return VStack(spacing: 8) {
      HStack(spacing: 8) {
        ForEach(topRow) { mood in moodChip(mood) }
      }
      HStack(spacing: 8) {
        ForEach(bottomRow) { mood in moodChip(mood) }
      }
    }
    .padding(.horizontal, 16)
  }

  private func moodChip(_ mood: Mood) -> some View {
    let selected = vm.selectedMood == mood
    return Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        vm.selectedMood = selected ? nil : mood
      }
    } label: {
      HStack(spacing: 5) {
        // White circle backing keeps icon visible against the filled mood-color background
        mood.image
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(selected ? 3 : 0)
          .background(Circle().fill(.white.opacity(selected ? 0.35 : 0)))
        Text(mood.rawValue)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .foregroundStyle(selected ? .white : mood.adaptiveColor)
      .background(
        Capsule()
          .fill(selected ? mood.adaptiveColor : mood.adaptiveColor.opacity(0.12))
      )
    }
    .buttonStyle(.plain)
    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: vm.selectedMood)
  }

  // MARK: - Mood headline

  @ViewBuilder
  private var moodHeadline: some View {
    if let mood = vm.selectedMood {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text("TodayI feel ")
          .font(.title2.weight(.semibold))
          .foregroundStyle(.primary)
        Text(mood.rawValue)
          .font(.title2.weight(.bold))
          .foregroundStyle(mood.adaptiveColor)
        Spacer()
        Text(Date().formatted("MMM d, yyyy"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .transition(.opacity.combined(with: .move(edge: .top)))
    } else {
      HStack {
        Text("How are you feeling today?")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text(Date().formatted("MMM d, yyyy"))
          .font(.subheadline)
          .foregroundStyle(.tertiary)
      }
      .transition(.opacity)
    }
  }

  // MARK: - Content card

  private var contentCard: some View {
    VStack(spacing: 0) {
      // Attachments at top of card
      if vm.isProcessingVideo || vm.videoPlayer != nil {
        videoSection
          .padding(.horizontal, 12)
          .padding(.top, 12)
      }

      if !vm.pickedImages.isEmpty {
        MediaSection(images: vm.pickedImages, onRemove: { vm.removeImage($0) })
          .padding(.horizontal, 12)
          .padding(.top, 12)
      }

      if let s = vm.linkString, let url = URL(string: s) {
        linkCard(url: url)
          .padding(.horizontal, 12)
          .padding(.top, 12)
      }

      // Text editor
      PlaceholderTextEditor(
        text: $vm.text,
        placeholder: "Write your thoughts for today…",
        minHeight: 160,
        maxHeight: 260
      )
      .padding(.horizontal, 4)
      .padding(.top, 4)
      .padding(.bottom, 4)

      // Character counter (non-premium)
      if !entitlements.isPremium {
        HStack {
          Spacer()
          Text("\(vm.remaining) left")
            .font(.caption)
            .foregroundStyle(vm.remaining < 30 ? .orange : Color(.tertiaryLabel))
            .padding(.trailing, 14)
            .padding(.bottom, 8)
        }
      }

      Divider()
        .padding(.horizontal, 12)

      // Inline action toolbar
      actionToolbar
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(
          vm.selectedMood?.adaptiveColor.opacity(0.25) ?? Color(.separator),
          lineWidth: 1
        )
    )
    .animation(.easeInOut(duration: 0.2), value: vm.selectedMood)
  }

  // MARK: - Inline action toolbar

  private var actionToolbar: some View {
    HStack(spacing: 6) {
      toolbarButton(icon: "photo", label: "Photo", enabled: true) {
        vm.tapPhoto()
      }
      toolbarButton(icon: "video", label: "Video", enabled: entitlements.isPremium) {
        vm.tapVideo()
      }
      toolbarButton(icon: "photo.on.rectangle", label: "Gallery", enabled: entitlements.isPremium) {
        vm.tapGallery()
      }
      toolbarButton(icon: "link", label: "Link", enabled: true) {
        vm.tapLink()
      }
      Spacer()
      if !entitlements.isPremium {
        Button {
          showPremium = true
        } label: {
          Label("Unlock all", systemImage: "star.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(moodGradient))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func toolbarButton(icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: icon)
          .font(.system(size: 18))
          .frame(width: 36, height: 30)
        Text(label)
          .font(.system(size: 10, weight: .medium))
      }
      .foregroundStyle(
        enabled
          ? (vm.selectedMood?.adaptiveColor ?? Color.accentColor)
          : Color(.tertiaryLabel)
      )
      .opacity(enabled ? 1 : 0.45)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }

  // MARK: - Privacy row

  private var privacyBinding: Binding<Bool> {
    Binding(
      get: { vm.isPublic },
      set: { newValue in
        if newValue && auth.isGuest {
          showAuth = true
        } else {
          vm.isPublic = newValue
        }
      }
    )
  }

  private var privacyRow: some View {
    HStack {
      PrivacyBadge(isPublic: privacyBinding)
      Spacer()
    }
  }

  // MARK: - Post toolbar button

  private var postToolbarButton: some View {
    Button {
      vm.pressPost()
    } label: {
      Text("Post")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(vm.canPost ? .white : Color(.secondaryLabel))
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
          Capsule()
            .fill(vm.canPost
              ? (vm.selectedMood?.adaptiveColor ?? Color.accentColor)
              : Color(.tertiarySystemFill))
        )
    }
    .buttonStyle(.plain)
    .disabled(!vm.canPost)
    .animation(.easeInOut(duration: 0.2), value: vm.canPost)
    .animation(.easeInOut(duration: 0.2), value: vm.selectedMood)
  }

  // MARK: - Video section (inside card)

  private var videoSection: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(.tertiarySystemBackground))
        .frame(height: 180)

      if let player = vm.videoPlayer {
        VideoPlayer(player: player)
          .frame(height: 180)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .onAppear { player.play() }
          .onDisappear { player.pause() }
      }

      if vm.isProcessingVideo {
        VStack(spacing: 8) {
          ProgressView().progressViewStyle(.circular)
          Text("Processing video…").font(.caption).foregroundStyle(.secondary)
        }
        .transition(.opacity)
      }

      if vm.videoPlayer != nil {
        VStack {
          HStack {
            Button { vm.clearVideo() } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .padding(8)
                .background(.thinMaterial, in: Circle())
            }
            .padding(.leading, 8).padding(.top, 8)
            Spacer()
          }
          Spacer()
        }
      }
    }
    .animation(.easeInOut, value: vm.isProcessingVideo)
  }

  // MARK: - Link card (inside card)

  private func linkCard(url: URL) -> some View {
    ZStack(alignment: .topTrailing) {
      Button { openURL(url) } label: {
        LinkPreviewView(url: url)
          .frame(height: 140)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .buttonStyle(.plain)

      Button { vm.clearLink() } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title3)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.primary)
          .padding(6)
          .background(.thinMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .padding(8)
    }
  }

  // MARK: - Preview sheet

  private var previewSheet: some View {
    Group {
      if let mem = postedMemory {
        NavigationStack {
          ScrollView {
            MemoryRow(memory: mem)
              .environmentObject(auth)
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

  // MARK: - ViewModel wiring

  private func configureViewModel() {
    vm.isPremium = entitlements.isPremium
    vm.onPost = { payload in
      guard let swiftManager, let uid = auth.userID else { return }
      let username = auth.username ?? "Me"
      do {
        if let model = try swiftManager.savePostPayload(
          payload,
          userID: uid,
          username: username,
          remoteProfilePhotoURL: auth.photoURL
        ) as MemoryModel? {
          postedMemory = model
          showPreview = true
          vm.clearAll()
        }
      } catch {
        print("Save failed: \(error)")
      }
    }
  }
}

// MARK: - View Modifiers

private struct MediaPickers: ViewModifier {
  @ObservedObject var vm: CreateMemoryViewModel
  let entitlements: EntitlementStore

  func body(content: Content) -> some View {
    content
      .photosPicker(isPresented: $vm.presentSinglePicker, selection: $vm.singleItem, matching: .images)
      .onChange(of: vm.singleItem) { _, _ in Task { await vm.handleSingleSelectionChange() } }
      .photosPicker(isPresented: $vm.presentMultiPicker, selection: $vm.galleryItems,
                    maxSelectionCount: entitlements.isPremium ? 12 : 1, matching: .images)
      .onChange(of: vm.galleryItems) { _, _ in Task { await vm.handleGallerySelectionChange() } }
      .photosPicker(isPresented: $vm.presentVideoPicker, selection: $vm.videoItem, matching: .videos)
      .onChange(of: vm.videoItem) { _, _ in Task { await vm.handleVideoSelectionChange() } }
  }
}

private struct LinkAlert: ViewModifier {
  @ObservedObject var vm: CreateMemoryViewModel

  func body(content: Content) -> some View {
    content.alert("Add a link", isPresented: $vm.showLinkPrompt) {
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
  }
}
