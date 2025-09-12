//
//  PickedImage.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/13/25.
//

import UIKit

struct PickedImage: Identifiable, Equatable {
  let id = UUID()
  let image: UIImage
  
  static func == (lhs: PickedImage, rhs: PickedImage) -> Bool {
    lhs.id == rhs.id
  }
}
