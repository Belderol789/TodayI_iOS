import SwiftUI
import Combine
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

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
  
  // Video picker
  @Published var presentVideoPicker: Bool = false
  @Published var videoItem: PhotosPickerItem? = nil
  
  // Keep exactly ONE video
  @Published private(set) var pendingVideoURL: URL? = nil
  @Published private(set) var videoThumbnail: UIImage? = nil
  
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
    clearVideo()
    singleItem = nil
    presentSinglePicker = true
  }
  
  func tapGallery() {
    // Reset then present the multi picker
    clearVideo()
    galleryItems = []
    presentMultiPicker = true
  }
  
  func tapLink() {
    clearVideo()
    clearImages()
    onAddLink?()
  }
  
  func tapVideo() {
    // Ensure single selection; reset any previous video
    clearImages()
    videoItem = nil
    presentVideoPicker = true
  }
  
  func pressPost() {
    guard let mood = selectedMood else { return }
    onPost?(mood, text, pickedImages)
  }
  
  // MARK: - PhotosPicker change handlers (called by the View’s .onChange)
  func handleSingleSelectionChange() async {
    guard let item = singleItem else { return }
    // Photos ⇒ ensure video is cleared
    clearVideo()
    if let img = await loadUIImage(from: item) {
      pickedImages = [PickedImage(image: img)]   // replace with 1
    }
    presentSinglePicker = false
    singleItem = nil
  }
  
  func handleGallerySelectionChange() async {
    guard !galleryItems.isEmpty else { return }
    // Photos ⇒ ensure video is cleared
    clearVideo()
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
  
  func handleVideoSelectionChange() async {
    guard let item = videoItem else { return }
    defer { videoItem = nil; presentVideoPicker = false }
    
    do {
      clearImages()
      // 1) Import as a FILE (not Data) using a Transferable
      let movie = try await item.loadTransferable(type: PickedMovie.self)
      guard var url = movie?.url else { return }
      
      // 2) Check duration
      let asset = AVURLAsset(url: url)
      let duration = await CMTimeGetSeconds(try asset.load(.duration))
      // 3) If > 30s, trim & transcode to .mp4 (720p to control size)
      if duration > 30.0 {
          url = try await exportFirst30SecondsMp4(from: asset)
      }
      
      // 4) Generate a thumbnail for UI
      if let thumb = await generateVideoThumbnail(from: url) {
        self.videoThumbnail = thumb
      }
      
      // 5) Keep exactly one pending video
      self.pendingVideoURL = url
    } catch {
      print("Video import failed: \(error)")
    }
  }
  
  // MARK: - Image helpers
  private func loadUIImage(from item: PhotosPickerItem) async -> UIImage? {
    if let data = try? await item.loadTransferable(type: Data.self),
       let ui = UIImage(data: data) {
      return ui
    }
    return nil
  }

  /// Trim to first 30s and transcode to H.264 .mp4 (720p).
  private func exportFirst30SecondsMp4(from asset: AVAsset) async throws -> URL {
    let start = CMTime(seconds: 0, preferredTimescale: 600)
    let dur   = CMTime(seconds: 30, preferredTimescale: 600)
    let range = CMTimeRange(start: start, duration: dur)
    
    let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    
    guard let exporter = AVAssetExportSession(asset: asset,
                                              presetName: AVAssetExportPreset1280x720)
    else { throw ExportError.cannotCreateExporter }
    
    exporter.timeRange = range
    exporter.shouldOptimizeForNetworkUse = true
    
    if #available(iOS 18.0, *) {
      // New iOS 18 API – avoids deprecated warning
      try await exporter.export(to: outURL, as: .mp4)
    } else {
      // Old callback API for iOS 15 and below
      exporter.outputURL = outURL
      exporter.outputFileType = .mp4
      try await withCheckedThrowingContinuation { cont in
        exporter.exportAsynchronously {
          switch exporter.status {
          case .completed: cont.resume()
          case .failed:    cont.resume(throwing: exporter.error ?? ExportError.unknown)
          case .cancelled: cont.resume(throwing: ExportError.cancelled)
          default:         cont.resume(throwing: ExportError.unknown)
          }
        }
      }
    }
    return outURL
  }
  
  enum ExportError: Error {
    case cannotCreateExporter, cancelled, unknown
  }
  
  private func generateVideoThumbnail(from url: URL) async -> UIImage? {
    await withCheckedContinuation { cont in
      let asset = AVURLAsset(url: url)
      let gen = AVAssetImageGenerator(asset: asset)
      gen.appliesPreferredTrackTransform = true
      let time = CMTime(seconds: 0.1, preferredTimescale: 600)
      
      // Correct async API: expects an array of NSValues
      gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
        if let cgImage {
          cont.resume(returning: UIImage(cgImage: cgImage))
        } else {
          cont.resume(returning: nil)
        }
      }
    }
  }
  
  // Public image ops (used by the view)
  func removeImage(_ id: UUID) {
    pickedImages.removeAll { $0.id == id }
  }
  
  func clearImages() { pickedImages.removeAll() }
  
  func clearVideo() {
    pendingVideoURL = nil
    videoThumbnail = nil
  }
  
  // MARK: - Text helpers
  private func enforceLimit() {
    if !isPremium, text.count > maxChars {
      text = String(text.prefix(maxChars))
    }
    remaining = max(0, maxChars - text.count)
  }
}
