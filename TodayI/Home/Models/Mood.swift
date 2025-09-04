//
//  Mood.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/3/25.
//

import SwiftUI

enum Mood: String, CaseIterable, Identifiable, Hashable  {
  case happy = "Happy"
  case sad = "Sad"
  case neutral = "Neutral"
  case disgust = "Disgust"
  case angry = "Angry"
  case surprise = "Surprise"
  case fear = "Fear"
  
  var id: String { rawValue }
  
  var color: Color {
    switch self {
    case .happy:
      return .yellow
    case .sad:
      return .blue
    case .neutral:
      return .gray
    case .disgust:
      return .green
    case .angry:
      return .red
    case .surprise:
      return .orange
    case .fear:
      return .purple
    }
  }
}
