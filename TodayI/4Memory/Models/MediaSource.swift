//
//  MediaSource.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/6/25.
//

import Foundation

enum MediaSource: Hashable {
  case local(path: String)           // file path on disk
  case remote(url: URL)              // network URL
}
