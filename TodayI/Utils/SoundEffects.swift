//
//  SoundEffects.swift
//  TodayI
//

import AVFoundation

/// Small, deliberate sounds — currently just the chime after saving a memory.
///
/// The session is `.ambient` on purpose: it obeys the ring/silent switch and mixes with
/// whatever is already playing, so a journal entry never cuts off someone's music or makes
/// noise in a quiet room. Sounds can also be turned off in Settings.
///
/// `post_chime.m4a` was synthesized for this app (two soft sine tones a fifth apart), so
/// there is no third-party licence attached to it.
@MainActor
enum SoundEffects {
  static let enabledKey = "soundEffectsEnabled"

  /// On unless the user turned it off. `UserDefaults.bool` would read a missing key as
  /// false, which would make sounds off by default.
  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  private static var player: AVAudioPlayer?

  static func playPostChime() {
    play("post_chime", ext: "m4a")
  }

  private static func play(_ name: String, ext: String) {
    guard isEnabled,
          let url = Bundle.main.url(forResource: name, withExtension: ext) else { return }
    do {
      try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
      // Kept in a static so it isn't deallocated mid-play.
      player = try AVAudioPlayer(contentsOf: url)
      player?.volume = 0.8
      player?.play()
    } catch {
      print("⚠️ Sound effect failed:", error)
    }
  }
}
