//
//  StringExtension.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/14/25.
//

import Foundation

extension String {
  var isVideoFile: Bool {
    let ext = (self as NSString).pathExtension.lowercased()
    return ["mp4", "mov", "m4v"].contains(ext)
  }
  
  var isImageFile: Bool {
    let ext = (self as NSString).pathExtension.lowercased()
    return ["jpg", "jpeg", "png", "heic", "heif"].contains(ext)
  }
}
