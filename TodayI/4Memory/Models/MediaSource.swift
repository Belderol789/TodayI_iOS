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
}
