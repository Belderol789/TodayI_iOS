import SwiftUI
import Combine
import UIKit
import PhotosUI

@MainActor
final class CreateMemoryViewModel: ObservableObject {
  // MARK: - Inputs / State
  @Published var selectedMood: Mood? = nil
  @Published var text: String = "" { didSet { enforceLimit() } }
  @Published var isPremium: Bool = false { didSet { enforceLimit() } }
  
  // Picked images the UI renders
  @Published private(set) var pickedImages: [PickedImage] = []
  
  // Character limit (enforced for non-premium)
  let maxChars: Int = 300
  @Published private(set) var remaining: Int = 300
  
  // MARK: - PhotosPicker presentation & selections (owned by VM)
  @Published var presentSinglePicker: Bool = false
  @Published var presentMultiPicker: Bool = false
  @Published var singleItem: PhotosPickerItem? = nil
  @Published var galleryItems: [PhotosPickerItem] = []
  
  // MARK: - Hooks (optional)
  var onAddLink: (() -> Void)?
  var onPost: ((Mood, String, [PickedImage]) -> Void)?
  
  // MARK: - Init
  init(isPremium: Bool = false, selectedMood: Mood? = nil, text: String = "") {
    self.isPremium = isPremium
    self.selectedMood = selectedMood
    self.text = text
    self.remaining = max(0, maxChars - text.count)
    enforceLimit()
  }
  
  // MARK: - Derived
  var canPost: Bool {
    selectedMood != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  
  // MARK: - Intents (called by the View)
  func choose(mood: Mood) { selectedMood = mood }
  
  func tapPhoto() {
    // Reset then present the single picker
    singleItem = nil
    presentSinglePicker = true
  }
  
  func tapGallery() {
    // Reset then present the multi picker
    galleryItems = []
    presentMultiPicker = true
  }
  
  func tapLink() { onAddLink?() }
  
  func tapVideo() { /* wire later */ }
  
  func pressPost() {
    guard let mood = selectedMood else { return }
    onPost?(mood, text, pickedImages)
  }
  
  // MARK: - PhotosPicker change handlers (called by the View’s .onChange)
  func handleSingleSelectionChange() async {
    guard let item = singleItem else { return }
    if let img = await loadUIImage(from: item) {
      pickedImages = [PickedImage(image: img)]   // replace with 1
    }
    presentSinglePicker = false
    singleItem = nil
  }
  
  func handleGallerySelectionChange() async {
    guard !galleryItems.isEmpty else { return }
    var imgs: [PickedImage] = []
    for item in galleryItems {
      if let img = await loadUIImage(from: item) {
        imgs.append(PickedImage(image: img))
      }
    }
    if !imgs.isEmpty { pickedImages.append(contentsOf: imgs) }
    presentMultiPicker = false
    galleryItems = []
  }
  
  // MARK: - Image helpers
  private func loadUIImage(from item: PhotosPickerItem) async -> UIImage? {
    if let data = try? await item.loadTransferable(type: Data.self),
       let ui = UIImage(data: data) {
      return ui
    }
    return nil
  }
  
  // Public image ops (used by the view)
  func removeImage(_ id: UUID) {
    pickedImages.removeAll { $0.id == id }
  }
  
  func clearImages() { pickedImages.removeAll() }
  
  // MARK: - Text helpers
  private func enforceLimit() {
    if !isPremium, text.count > maxChars {
      text = String(text.prefix(maxChars))
    }
    remaining = max(0, maxChars - text.count)
  }
}
