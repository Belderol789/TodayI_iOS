//
//  MediaSource.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/6/25.
//

import Foundation

enum MediaSource {
  case localImage(path: String)
  case remoteImage(url: URL)
  case localVideo(path: String)
  case remoteVideo(url: URL)
  case localAudio(path: String)
  case remoteAudio(url: URL)
  /// Rules-protected media with no download token — a Personal entry's photo, video or
  /// voice note. Carries a storage path, not a URL, and is fetched through
  /// `ProtectedMediaStore` so the owner-only rule is actually enforced.
  case protectedImage(path: String)
  case protectedVideo(path: String)
  case protectedAudio(path: String)
}
