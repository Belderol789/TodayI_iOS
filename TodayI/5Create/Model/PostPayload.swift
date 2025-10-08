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
  let images: [PickedImage]       // empty if not using photos
  let videoURL: URL?              // non-nil if posting a video
  let linkString: String?         // non-nil if posting a link
}
