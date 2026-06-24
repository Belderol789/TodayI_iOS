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
}
