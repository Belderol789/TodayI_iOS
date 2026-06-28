import SwiftUI
import AVFoundation

struct AudioPlayerRow: View {
  let source: MediaSource
  let moodColor: Color

  @State private var player: AVAudioPlayer?
  @State private var isPlaying = false
  @State private var duration: TimeInterval = 0
  @State private var currentTime: TimeInterval = 0
  @State private var isLoading = false
  @State private var timer: Timer?

  var body: some View {
    HStack(spacing: 12) {
      Button { togglePlayback() } label: {
        Image(systemName: isLoading ? "ellipsis" : (isPlaying ? "pause.circle.fill" : "play.circle.fill"))
          .font(.system(size: 36))
          .foregroundStyle(moodColor)
          .symbolEffect(.pulse, isActive: isLoading)
      }
      .buttonStyle(.plain)
      .disabled(isLoading)

      VStack(alignment: .leading, spacing: 6) {
        // Progress bar
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(moodColor.opacity(0.15)).frame(height: 4)
            Capsule()
              .fill(moodColor)
              .frame(width: duration > 0 ? geo.size.width * (currentTime / duration) : 0, height: 4)
              .animation(.linear(duration: 0.1), value: currentTime)
          }
        }
        .frame(height: 4)

        HStack {
          Text(formatTime(currentTime))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          Spacer()
          Text(formatTime(duration))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onAppear { preparePlayer() }
    .onDisappear { tearDown() }
  }

  // MARK: - Player lifecycle

  private func preparePlayer() {
    switch source {
    case .localAudio(let path):
      let url = URL(fileURLWithPath: path)
      loadPlayer(from: url)
    case .remoteAudio(let url):
      // Stream directly — AVAudioPlayer handles remote URLs
      isLoading = true
      Task {
        do {
          let (data, _) = try await URLSession.shared.data(from: url)
          await MainActor.run {
            loadPlayer(from: data)
            isLoading = false
          }
        } catch {
          await MainActor.run { isLoading = false }
        }
      }
    default:
      break
    }
  }

  private func loadPlayer(from url: URL) {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      player = try AVAudioPlayer(contentsOf: url)
      player?.prepareToPlay()
      duration = player?.duration ?? 0
    } catch {
      print("AudioPlayerRow: failed to load \(url): \(error)")
    }
  }

  private func loadPlayer(from data: Data) {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      player = try AVAudioPlayer(data: data)
      player?.prepareToPlay()
      duration = player?.duration ?? 0
    } catch {
      print("AudioPlayerRow: failed to load remote audio: \(error)")
    }
  }

  private func togglePlayback() {
    guard let player else { return }
    if isPlaying {
      player.pause()
      stopTimer()
      isPlaying = false
    } else {
      try? AVAudioSession.sharedInstance().setActive(true)
      player.play()
      isPlaying = true
      startTimer()
    }
  }

  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
      guard let player else { stopTimer(); return }
      currentTime = player.currentTime
      if !player.isPlaying {
        isPlaying = false
        currentTime = 0
        stopTimer()
      }
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func tearDown() {
    player?.stop()
    stopTimer()
    isPlaying = false
  }

  private func formatTime(_ t: TimeInterval) -> String {
    let s = Int(t)
    return String(format: "%d:%02d", s / 60, s % 60)
  }
}
