import SwiftUI
import PhotosUI

struct CreateMemoryView: View {
  @EnvironmentObject private var entitlements: EntitlementStore
  @Environment(\.dismiss) private var dismiss
  @StateObject private var vm = CreateMemoryViewModel()
  
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          header
          mediaSection
          journalSection
          counterSection
          quickActions
        }
        .padding(.top, 10)
      }
      .navigationTitle("Create")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) { postButton }
      .onAppear {
        vm.isPremium = entitlements.isPremium
        vm.onPost = { mood, text, images in
          // save & dismiss
          dismiss()
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
    }
  }
}

// MARK: - Sections
private extension CreateMemoryView {
  
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
            .padding(.horizontal, 4)
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
  
  var counterSection: some View {
    HStack {
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
  
  var quickActions: some View {
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
        action: { vm.tapLink() },
        isEnabled: true,
        color: vm.selectedMood?.adaptiveColor
      )
    }
    .padding(.horizontal)
    .padding(.bottom, 120)
  }
  
  var postButton: some View {
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

// MARK: - Media section (one image full-width or a horizontal gallery)

private struct MediaSection: View {
  let images: [PickedImage]
  var onRemove: (UUID) -> Void
  
  var body: some View {
    if images.count == 1, let item = images.first {
      ZStack(alignment: .topTrailing) {
        Image(uiImage: item.image)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        
        removeButton(id: item.id)
      }
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(images) { item in
            ZStack(alignment: .topTrailing) {
              Image(uiImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              
              removeButton(id: item.id)
            }
          }
        }
        .frame(height: 160)
      }
    }
  }
  
  @ViewBuilder
  private func removeButton(id: UUID) -> some View {
    Button {
      onRemove(id)
    } label: {
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
