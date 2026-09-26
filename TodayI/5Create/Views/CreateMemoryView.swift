import SwiftUI
import SwiftData
import PhotosUI
import AVKit
import UserNotifications

struct CreateMemoryView: View {
  @EnvironmentObject private var entitlements: EntitlementStore
  @EnvironmentObject private var auth: AuthStore
  @Environment(\.modelContext) private var context
  @Environment(\.swiftDataManager) private var swiftManager
  @EnvironmentObject private var globalFeed: GlobalFeedViewModel
  @Binding var tabSelection: AppTab
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

  @AppStorage("hasPostedOnce") private var hasPostedOnce = false
  @State private var showNotifPrompt = false
  /// Content-filter state. `showSupport` is never a gate — see `attemptPost()`.
  @State private var showSupport = false
  /// True when the support sheet is explaining that we kept the entry Personal.
  @State private var redirectedToPersonal = false
  @State private var showBlockedAlert = false
  @State private var showPIIAlert = false
  /// How many memories today already holds — drives the free-tier notice.
  @State private var todayMemoryCount = 0

  var body: some View {
    NavigationStack {
      ScrollView {

        VStack(spacing: 0) {
          secondMemoryNotice

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

          storageNotice
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 100)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
      .navigationTitle("Create")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        // Both live in the nav bar so they stay reachable while the keyboard is up —
        // the privacy control used to sit under the editor, which the keyboard covers
        // exactly when you're most likely to reconsider posting publicly.
        ToolbarItemGroup(placement: .topBarTrailing) {
          privacyToolbarButton
          postToolbarButton
        }
      }
      .onAppear {
        configureViewModel()
        refreshTodayMemoryCount()
      }
      .onChange(of: entitlements.isPremium) { _, new in vm.isPremium = new }
      .onChange(of: auth.isRegisteredUser) { _, isRegistered in
        if isRegistered && !auth.isRestricted { vm.isPublic = true }
      }
      .onChange(of: auth.isRestricted) { _, restricted in
        if restricted { vm.isPublic = false }
      }
      .modifier(MediaPickers(vm: vm, entitlements: entitlements))
      .modifier(LinkAlert(vm: vm))
      .sheet(isPresented: $showPreview, onDismiss: handlePreviewDismiss) { previewSheet }
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
      .alert("Build a journaling habit?", isPresented: $showNotifPrompt) {
        Button("Yes, remind me daily") {
          Task { await NotificationManager.shared.configure() }
        }
        Button("Maybe later", role: .cancel) {}
      } message: {
        Text("Want to get notified to create a habit of journalling daily?")
      }
      .alert("This can't go on the Global feed", isPresented: $showBlockedAlert) {
        Button("Keep it Personal") {
          vm.isPublic = false
          postIgnoringWarnings()
        }
        Button("Edit", role: .cancel) {}
      } message: {
        Text("Posts on the Global feed can't contain slurs or threats. You can still save this entry just for yourself.")
      }
      .alert("Sharing contact details?", isPresented: $showPIIAlert) {
        Button("Post to Global", role: .destructive) { postIgnoringWarnings() }
        Button("Keep it Personal") {
          vm.isPublic = false
          postIgnoringWarnings()
        }
        Button("Edit", role: .cancel) {}
      } message: {
        Text("This looks like it contains a phone number or email address. Anyone can read posts on the Global feed.")
      }
      .sheet(isPresented: $showSupport) { supportSheet }
    }
  }

  // MARK: - Support sheet

  /// Shown *after* the entry is safely saved, never before. It asks nothing and changes
  /// nothing — the post is already written exactly as the user wrote it.
  private var supportSheet: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("That sounded like a hard day.")
            .font(.title2.weight(.semibold))
          Text(redirectedToPersonal
               ? "Whenever you're ready, your entry will be saved exactly as you wrote it — kept Personal rather than posted to the Global feed. Nothing is flagged or reported. If you'd rather talk to someone, these are free and confidential."
               : "Whenever you're ready, your entry will be saved exactly as you wrote it. Nothing is flagged or reported. If you'd rather talk to someone, these are free and confidential.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          ForEach(ContentModeration.crisisResources) { resource in
            VStack(alignment: .leading, spacing: 2) {
              Text(resource.name).font(.subheadline.weight(.semibold))
              Text(resource.contact).font(.title3.weight(.bold)).foregroundStyle(.tint)
              Text(resource.region).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
          }
        }
        .padding(20)
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 10) {
          // Primary, and deliberately so. Nothing here is a gate.
          Button(action: saveAfterSupport) {
            Text("Save anyway")
              .font(.subheadline.weight(.semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 13)
              .background(Capsule().fill(Color.accentColor))
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)

          Button("Keep writing") { showSupport = false }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.bar)
      }
      .navigationTitle("You're not alone")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(false)
    }
    .presentationDetents([.medium, .large])
  }

  // MARK: - Free-tier notice

  /// Non-blocking: posting a second memory still works, it just won't be visible on
  /// the free tier. Saying so up front beats letting the entry quietly disappear —
  /// and the upsell lands at the moment of demonstrated intent, without interrupting
  /// the writing itself.
  @ViewBuilder
  private var secondMemoryNotice: some View {
    if !entitlements.isPremium && todayMemoryCount > 0 {
      Button { showPremium = true } label: {
        HStack(spacing: 10) {
          Image(systemName: "sparkles")
            .foregroundStyle(.white)
          VStack(alignment: .leading, spacing: 2) {
            Text("You've already captured today")
              .font(.subheadline.weight(.semibold))
            Text("Free keeps your latest memory. Premium keeps every one.")
              .font(.caption)
              .opacity(0.9)
          }
          Spacer(minLength: 8)
          Text("Unlock")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.22)))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(moodGradient)
        )
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("You have already captured today. Premium keeps every memory.")
      .accessibilityHint("Opens Premium.")
    }
  }

  /// Local count only — no network. Cheap enough to redo on every appearance.
  private func refreshTodayMemoryCount() {
    let key = Date().today.formattedDayKeyLocal()
    var fetch: FetchDescriptor<MemoryModel>
    if let uid = auth.userID {
      fetch = FetchDescriptor<MemoryModel>(
        predicate: #Predicate { $0.dayKey == key && $0.userID == uid }
      )
    } else {
      fetch = FetchDescriptor<MemoryModel>(predicate: #Predicate { $0.dayKey == key })
    }
    todayMemoryCount = (try? context.fetch(fetch).count) ?? 0
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

      if vm.isRecording || vm.pendingAudioURL != nil {
        audioSection
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
          Button("Premium removes the limit") { showPremium = true }
            .font(.caption2.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(vm.selectedMood?.adaptiveColor ?? Color.accentColor)
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
    HStack(spacing: 4) {
      // Free tier: Photo, Mic, Link
      toolbarButton(icon: "photo", label: "Photo", enabled: true) { vm.tapPhoto() }
      toolbarButton(
        icon: vm.isRecording ? "stop.circle.fill" : (vm.pendingAudioURL != nil ? "mic.fill" : "mic"),
        label: vm.isRecording ? "Stop" : "Mic",
        enabled: true,
        tint: vm.isRecording ? .red : nil
      ) { vm.tapMic() }
      toolbarButton(icon: "link", label: "Link", enabled: true) { vm.tapLink() }

      // Divider between free and premium
      Rectangle()
        .fill(Color(.separator))
        .frame(width: 1, height: 28)
        .padding(.horizontal, 4)

      // Premium tier: Video, Gallery
      toolbarButton(icon: "video", label: "Video", enabled: entitlements.isPremium) {
        if entitlements.isPremium { vm.tapVideo() } else { showPremium = true }
      }
      toolbarButton(icon: "photo.on.rectangle", label: "Gallery", enabled: entitlements.isPremium) {
        if entitlements.isPremium { vm.tapGallery() } else { showPremium = true }
      }

      Spacer()

      if !entitlements.isPremium {
        Button { showPremium = true } label: {
          Label("Unlock", systemImage: "star.fill")
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

  private func toolbarButton(icon: String, label: String, enabled: Bool, tint: Color? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: icon)
          .font(.system(size: 18))
          .frame(width: 36, height: 30)
        Text(label)
          .font(.system(size: 10, weight: .medium))
      }
      .foregroundStyle(
        tint ?? (enabled
          ? (vm.selectedMood?.adaptiveColor ?? Color.accentColor)
          : Color(.tertiaryLabel))
      )
      .opacity(enabled ? 1 : 0.45)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Privacy row

  private var privacyBinding: Binding<Bool> {
    Binding(
      get: { vm.isPublic },
      set: { newValue in
        if newValue && auth.isGuest {
          showAuth = true
        } else if newValue && auth.isRestricted {
          // Silently block — badge stays private
        } else {
          vm.isPublic = newValue
        }
      }
    )
  }

  /// Icon-only toggle that rides in the navigation bar; the globe/padlock carries
  /// the state. The badge itself lives under the editor no longer.
  private var privacyToolbarButton: some View {
    PrivacyBadge(isPublic: privacyBinding, compact: true)
      .disabled(auth.isRestricted)
      .opacity(auth.isRestricted ? 0.5 : 1)
  }

  /// Only the restriction notice remains inline — it's an explanation, not a control.
  /// Where entries actually live, said plainly and permanently.
  ///
  /// Deliberately **not** onboarding. A one-time card gets swiped past and forgotten,
  /// and this is a promise we'll be held to — "I deleted the app and lost two years of
  /// journals" is the worst review this app can get. So it sits under the privacy
  /// control, where someone is already thinking about where this entry goes.
  ///
  /// Styled as a quiet footnote rather than an upsell banner: `secondMemoryNotice`
  /// already carries the gradient pitch, and two of those on one screen is nagging.
  @ViewBuilder
  private var storageNotice: some View {
    if !entitlements.isPremium {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "iphone")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text("Saved on this device. ")
          .foregroundStyle(.secondary)
        + Text("Premium backs up your journal.")
          .foregroundStyle(.secondary)
          .underline()
      }
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture { showPremium = true }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Entries are saved on this device only. Premium backs up your journal.")
      .accessibilityHint("Opens Premium.")
    }
  }

  @ViewBuilder
  private var privacyRow: some View {
    if auth.isRestricted {
      Text("Your account is currently restricted from public posts.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Post toolbar button

  private var postToolbarButton: some View {
    Button {
      attemptPost()
    } label: {
      // "Post" implies an audience. A Personal entry has none — it's a save.
      Text(vm.isPublic ? "Post" : "Save")
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
    .animation(.easeInOut(duration: 0.2), value: vm.isPublic)
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

  // MARK: - Audio section (inside card)

  private var audioSection: some View {
    ZStack(alignment: .topTrailing) {
      HStack(spacing: 12) {
        // Play/Stop or mic-pulse icon
        Button {
          if vm.isRecording {
            vm.stopRecording()
          } else {
            vm.togglePlayback()
          }
        } label: {
          Image(systemName: vm.isRecording ? "stop.circle.fill" : (vm.isPlayingAudio ? "pause.circle.fill" : "play.circle.fill"))
            .font(.system(size: 36))
            .foregroundStyle(vm.selectedMood?.adaptiveColor ?? Color.accentColor)
            .symbolEffect(.pulse, isActive: vm.isRecording)
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 4) {
          Text(vm.isRecording ? "Recording…" : "Voice Note")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)

          // Animated waveform bars
          WaveformView(isActive: vm.isRecording || vm.isPlayingAudio,
                       color: vm.selectedMood?.adaptiveColor ?? Color.accentColor)

          Text(formatDuration(vm.recordingDuration))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Spacer()
      }
      .padding(12)
      .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      if !vm.isRecording {
        Button { vm.clearAudio() } label: {
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
    .animation(.easeInOut(duration: 0.2), value: vm.isRecording)
    .animation(.easeInOut(duration: 0.2), value: vm.isPlayingAudio)
  }

  private func formatDuration(_ t: TimeInterval) -> String {
    let total = Int(t)
    return String(format: "%d:%02d", total / 60, total % 60)
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

  // MARK: - Content filter

  /// Runs the client-side filter, then posts.
  ///
  /// Three findings, three deliberately different responses:
  ///
  /// - **Hate speech / threats** block a *public* post only. The entry is still yours to
  ///   keep privately; what's refused is the Global feed, not the journal.
  /// - **Contact details** warn but never block — sometimes people mean to share them.
  /// - **Self-harm never blocks and never delays.** The post goes through untouched and
  ///   support is offered *afterwards*. Gating someone's lowest moment behind a modal
  ///   would teach them this app is a bad place to be honest, which is the opposite of
  ///   what it is for. Nothing is logged, flagged or reported.
  private func attemptPost() {
    let findings = ContentModeration.scan(vm.text)

    if vm.isPublic, !findings.isDisjoint(with: ContentModeration.blocking) {
      showBlockedAlert = true
      return
    }

    // Self-harm: offer support *before* saving, then let them save anyway.
    //
    // This used to save first and show resources afterwards, which meant the moment had
    // already passed — and when the entry was Global it had also gone out to strangers
    // before anyone offered help. Showing the card first catches the person while
    // they're still in it.
    //
    // It is not a gate. "Save anyway" is the primary action and nothing is refused,
    // flagged or reported. The one thing that does change is the destination: the entry
    // is kept Personal, because the Global feed is day-scoped and anonymous with no
    // support structure, so it can't help them and publishing it risks harm to whoever
    // reads it.
    if findings.contains(.selfHarm) {
      redirectedToPersonal = vm.isPublic
      showSupport = true
      return
    }

    if vm.isPublic, findings.contains(.personalInfo) {
      showPIIAlert = true
      return
    }

    vm.pressPost()
  }

  /// Completes the save the support card interrupted.
  private func saveAfterSupport() {
    if redirectedToPersonal { vm.isPublic = false }
    showSupport = false
    vm.pressPost()
  }

  /// Posts without re-running the filter — used by the "post anyway" paths.
  private func postIgnoringWarnings() {
    let findings = ContentModeration.scan(vm.text)
    vm.pressPost()
    if findings.contains(.selfHarm) { showSupport = true }
  }

  // MARK: - Post-preview hook

  private func handlePreviewDismiss() {
    guard !hasPostedOnce else { return }
    hasPostedOnce = true
    Task {
      let status = await UNUserNotificationCenter.current().notificationSettings()
      if status.authorizationStatus == .notDetermined {
        await MainActor.run { showNotifPrompt = true }
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
          vm.clearAll()
          refreshTodayMemoryCount()

          if model.isPublic {
            // A public post belongs in the feed, not behind a modal. Hand it to the
            // shared feed model so it's already at the top when the tab appears —
            // the upload is async and the feed query has no ordering, so waiting on
            // the server would be slower and wouldn't put it first anyway.
            globalFeed.prepend(MemoryDTO(from: model))
            tabSelection = .global
            // The notification prompt normally rides on the preview's dismissal,
            // which never happens down this path.
            handlePreviewDismiss()
          } else {
            postedMemory = model
            showPreview = true
          }
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

// MARK: - Waveform animation

private struct WaveformView: View {
  let isActive: Bool
  let color: Color
  private let barCount = 12
  @State private var phases: [Double] = (0..<12).map { Double($0) * 0.3 }

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<barCount, id: \.self) { i in
        RoundedRectangle(cornerRadius: 2)
          .fill(color.opacity(isActive ? 1.0 : 0.35))
          .frame(width: 3, height: isActive ? (8 + 12 * abs(sin(phases[i]))) : 4)
          .animation(
            isActive
              ? .easeInOut(duration: 0.4 + Double(i) * 0.05).repeatForever(autoreverses: true)
              : .easeOut(duration: 0.2),
            value: isActive
          )
      }
    }
    .frame(height: 24)
    .onAppear {
      guard isActive else { return }
      for i in 0..<barCount {
        withAnimation(.easeInOut(duration: 0.4 + Double(i) * 0.05).repeatForever(autoreverses: true)) {
          phases[i] += .pi
        }
      }
    }
    .onChange(of: isActive) { _, active in
      if active {
        for i in 0..<barCount {
          withAnimation(.easeInOut(duration: 0.4 + Double(i) * 0.05).repeatForever(autoreverses: true)) {
            phases[i] += .pi
          }
        }
      }
    }
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
