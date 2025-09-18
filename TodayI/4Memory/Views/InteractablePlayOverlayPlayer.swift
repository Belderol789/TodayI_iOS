//
//  InteractablePlayOverlayPlayer.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/18/25.
//

import SwiftUI
import AVKit

struct InteractablePlayOverlayPlayer: View {
  let url: URL
  var cornerRadius: CGFloat
  var minHeight: CGFloat
  
  @State private var player: AVPlayer
  @State private var isPlaying = false
  @State private var timeObserver: Any? = nil
  
  init(url: URL, cornerRadius: CGFloat, minHeight: CGFloat) {
    self.url = url
    self.cornerRadius = cornerRadius
    self.minHeight = minHeight
    _player = State(initialValue: AVPlayer(url: url))
  }
  
  var body: some View {
    ZStack {
      VideoPlayer(player: player)
        .onAppear { startObserving() }
        .onDisappear { stopObserving() }
      
      if !isPlaying {
        Button {
          player.play()
        } label: {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 64, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .shadow(radius: 6)
        }
        .buttonStyle(.plain)
        .padding()
      }
    }
    .frame(maxWidth: .infinity, minHeight: minHeight)
    .background(Color.black.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
  
  // MARK: - Observing
  
  private func startObserving() {
    // Reflect timeControlStatus → isPlaying
    let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
      let playing = player.timeControlStatus == .playing
      if playing != isPlaying { isPlaying = playing }
    }
    // Reset overlay when the video ends
    NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main
    ) { _ in
      isPlaying = false
      player.seek(to: .zero)
    }
  }
  
  private func stopObserving() {
    if let token = timeObserver {
      player.removeTimeObserver(token)
      timeObserver = nil
    }
    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
    player.pause()
  }
}
