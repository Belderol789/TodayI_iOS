//
//  PostPayload.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/14/25.
//

import Foundation

struct PostPayload {
  let mood: Mood
  let isPublic: Bool
  let isPremium: Bool
  let text: String
  let images: [PickedImage]
  let videoURL: URL?
  let audioURL: URL?
  let linkString: String?
  /// The author marked this post sensitive, or accepted the flag when a sensitive word
  /// was detected. Blurs it in the Global feed; has no effect on a Personal entry.
  var isSensitive: Bool = false
}
