import SwiftUI

// MARK: - CreateMemoryView

struct CreateMemoryView: View {
  @EnvironmentObject private var entitlements: EntitlementStore
  @Environment(\.dismiss) private var dismiss
  
  // Form state
  @State private var selectedMood: Mood? = nil
  @State private var text: String = ""
  @State private var remaining: Int = 300
  
  private let maxChars = 300
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        header
        // Journal text area (no border, as requested)
        ZStack(alignment: .topLeading) {
          if text.isEmpty {
            Text("Write your thoughts for today…")
              .foregroundStyle(.secondary)
              .padding(.horizontal, 4)
              .padding(.top, 8)
          }
          TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 160, maxHeight: 220)
            .onChange(of: text) { _, newValue in
              if entitlements.isPremium {
                text = newValue
              } else {
                if newValue.count > maxChars {
                  text = String(newValue.prefix(maxChars))
                }
                remaining = max(0, maxChars - text.count)
              }
            }
        }
        .padding(.horizontal)
        
        // character counter
        HStack {
          Spacer()
          if entitlements.isPremium {
            PremiumPill(isPremium: entitlements.isPremium)
          } else {
            Text("\(remaining) left")
              .font(.caption)
              .foregroundStyle(remaining < 20 ? .orange : .secondary)
          }
        }
        .padding(.horizontal)
        
        // Quick actions
        HStack(spacing: 12) {
          QuickActionButton(
            title: "Photo", systemImage: "photo",
            action: { /* open photo picker */ },
            isEnabled: true,
            color: selectedMood?.adaptiveColor
          )
          QuickActionButton(
            title: "Video", systemImage: "video",
            action: { /* open video picker */ },
            isEnabled: entitlements.isPremium,
            color: selectedMood?.adaptiveColor
          )
          QuickActionButton(
            title: "Gallery", systemImage: "photo.on.rectangle",
            action: { /* open multi-image picker */ },
            isEnabled: entitlements.isPremium,
            color: selectedMood?.adaptiveColor
          )
          QuickActionButton(
            title: "Link", systemImage: "link",
            action: { /* add URL */ },
            isEnabled: true,
            color: selectedMood?.adaptiveColor
          )
        }
        Spacer()
      }
      .navigationTitle("Create")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            // save action (validate mood + text)
          } label: {
            Text("Post")
              .font(.headline.bold())
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
              .background(
                Capsule().fill(selectedMood != nil ? selectedMood!.adaptiveColor : Color(.systemBackground).opacity(0.85))
              )
              .foregroundStyle(Color(.systemBackground))
              .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
          }
          .disabled(selectedMood == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
  
  // MARK: Header (Today I feel + mood dropdown with premium styling)
  var header: some View {
    HStack(spacing: 10) {
      Text("TodayI feel")
        .font(.headline)
      
      Menu {
        ForEach(Mood.allCases) { mood in
          Button {
            selectedMood = mood
          } label: {
            HStack {
              if entitlements.isPremium {
                Text(mood.rawValue)
                  .font(.headline.bold())
                  .padding(.horizontal, 10)
                  .padding(.vertical, 4)
                  .background(
                    Capsule().fill(Color(.systemBackground).opacity(0.85))
                  )
                  .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
              } else {
                Text(mood.rawValue)
                  .font(.headline.bold())
              }
              mood.image
            }
          }
          .tint(mood.adaptiveColor)
        }
      } label: {
        if let mood = selectedMood {
          HStack {
            if entitlements.isPremium {
              Text(mood.rawValue)
                .font(.headline.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                  Capsule().fill(mood.adaptiveColor)
                )
                .foregroundStyle(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
            } else {
              Text(mood.rawValue)
                .font(.headline.bold())
                .foregroundStyle((mood.adaptiveColor))
            }
            MoodIcon(mood: mood, size: 25)
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
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
        }
      }
      
      Spacer()
    }
    .padding(.horizontal)
    .padding(.top, 4)
  }
}

// MARK: - PREVIEWS

/// Simple preview stub for your EntitlementStore.
/// Your real app already provides EntitlementStore; this is just for previews.
#Preview("Premium") {
  PreviewWrapper(isPremium: true)
}

#Preview("Free") {
  PreviewWrapper(isPremium: false)
}

private struct PreviewWrapper: View {
  @StateObject private var entitlement: EntitlementStore
  
  init(isPremium: Bool) {
    let store = EntitlementStore()
    store.isPremium = isPremium
    _entitlement = StateObject(wrappedValue: store)
  }
  
  var body: some View {
    CreateMemoryView()
      .environmentObject(entitlement)
  }
}
