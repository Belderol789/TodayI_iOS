//
//  URLExtension.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/14/25.
//

import Foundation

extension URL {
  var isVideoFile: Bool { path.isVideoFile }
  var isImageFile: Bool { path.isImageFile }
}
