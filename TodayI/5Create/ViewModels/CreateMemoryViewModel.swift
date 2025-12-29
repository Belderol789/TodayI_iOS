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
  @Published var isPublic: Bool = true
  
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
  @Published var videoPlayer: AVPlayer?
  private var loopObserver: NSObjectProtocol?
  @Published private(set) var pendingVideoURL: URL? = nil
  @Published private(set) var videoThumbnail: UIImage? = nil
  @Published var isProcessingVideo = false
  
  // Link
  @Published var linkString: String? = nil
  @Published var showLinkPrompt = false
  @Published var tempLinkInput = ""
  
  // MARK: - Hooks (optional)
  var onAddLink: (() -> Void)?
  var onPost: ((PostPayload) -> Void)?
  
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
    selectedMood != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessingVideo
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
    showLinkPrompt = true
  }
  
  func tapVideo() {
    // Ensure single selection; reset any previous video
    clearImages()
    videoItem = nil
    presentVideoPicker = true
  }
  
  func pressPost() {
    guard let mood = selectedMood else { return }
    let payload = PostPayload(
      mood: mood,
      isPublic: isPublic,
      isPremium: isPremium,
      text: text,
      images: pickedImages,
      videoURL: pendingVideoURL,
      linkString: linkString
    )
    onPost?(payload)
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
  
  @MainActor
  func handleVideoSelectionChange() async {
    guard let item = videoItem else { return }
    
    isProcessingVideo = true
    presentVideoPicker = false
    
    defer {
      isProcessingVideo = false
      videoItem = nil
    }
    
    do {
      clearImages()
      
      // 1) Import as file
      guard var url = try await item.loadTransferable(type: PickedMovie.self)?.url else { return }
      
      // 2) Check duration / trim
      let asset = AVURLAsset(url: url)
      let duration = try await asset.load(.duration).seconds
      if duration > 30.0 {
        url = try await exportFirst30SecondsMp4(from: asset)
      }
      
      // 3) Thumbnail (safe on main because we're @MainActor)
      videoThumbnail = await generateVideoThumbnail(from: url)
      
      // 4) Assign once
      pendingVideoURL = url
      configurePlayer(with: url, autoplay: true, loop: true, muted: false)
      
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
  
  private func configurePlayer(with url: URL,
                               autoplay: Bool = true,
                               loop: Bool = true,
                               muted: Bool = true) {
    // Clean up any previous observer
    if let obs = loopObserver {
      NotificationCenter.default.removeObserver(obs)
      loopObserver = nil
    }
    
    let player = AVPlayer(url: url)
    player.isMuted = muted
    player.actionAtItemEnd = .none
    self.videoPlayer = player
    
    if loop {
      loopObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: player.currentItem,
        queue: .main
      ) { [weak player] _ in
        player?.seek(to: .zero)
        player?.play()
      }
    }
    if autoplay { player.play() }
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
  
  func clearAll() {
    clearVideo()
    clearImages()
    clearLink()
    selectedMood = nil
    text = ""
  }
  
  // Public image ops (used by the view)
  func removeImage(_ id: UUID) {
    pickedImages.removeAll { $0.id == id }
  }
  
  func clearImages() {
    pickedImages.removeAll()
  }
  
  func clearVideo() {
    videoPlayer?.pause()
    videoPlayer = nil
    if let obs = loopObserver {
      NotificationCenter.default.removeObserver(obs)
      loopObserver = nil
    }
    pendingVideoURL = nil
    videoThumbnail = nil
  }
  
  func clearLink() {
    linkString = nil
  }
  
  // MARK: - Text helpers
  private func enforceLimit() {
    if !isPremium, text.count > maxChars {
      text = String(text.prefix(maxChars))
    }
    remaining = max(0, maxChars - text.count)
  }
}

extension CreateMemoryViewModel {
  var attachmentIndicatorText: String? {
    if !pickedImages.isEmpty {
      return pickedImages.count == 1 ? "📷 1 photo" : "📷 \(pickedImages.count) photos"
    } else if pendingVideoURL != nil {
      return "🎬 1 video"
    } else if let link = linkString, !link.isEmpty {
      // Keep it short (strip scheme)
      let display = link.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
      return "🔗 \(display)"
    } else {
      return nil
    }
  }
}
