import SwiftUI
import PhotosUI

@MainActor
final class PhotoPickerManager: ObservableObject {
  @Published var images: [UIImage] = []
  
  func load(items: [PhotosPickerItem]) async {
    guard !items.isEmpty else { return }
    for item in items {
      if let img = await loadUIImage(from: item) {
        images.append(img)
      }
    }
  }
  
  func clear() { images.removeAll() }
  func remove(at index: Int) {
    guard images.indices.contains(index) else { return }
    images.remove(at: index)
  }
  
  // MARK: - Helpers
  
  private func loadUIImage(from item: PhotosPickerItem) async -> UIImage? {
    // Preferred: raw image Data (works for HEIC/PNG/JPEG, etc.)
    if let data = try? await item.loadTransferable(type: Data.self),
       let ui = UIImage(data: data) {
      return ui
    }
    // Fallback: SwiftUI.Image -> UIImage via ImageRenderer (iOS 16+)
    if let swiftUIImage = try? await item.loadTransferable(type: Image.self) {
      let renderer = ImageRenderer(content: swiftUIImage)
      renderer.scale = UIScreen.main.scale
      return renderer.uiImage
    }
    return nil
  }
}
