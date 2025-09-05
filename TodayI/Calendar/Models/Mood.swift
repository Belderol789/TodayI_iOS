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
  
  func color(for scheme: ColorScheme) -> Color {
    switch self {
    case .happy:
      return scheme == .dark
      ? Color(red: 0.95, green: 0.72, blue: 0.20)  // rich golden
      : Color(red: 0.99, green: 0.82, blue: 0.32)  // warm yellow
    case .sad:
      return scheme == .dark
      ? Color(red: 0.20, green: 0.38, blue: 0.70)  // deep muted blue
      : Color(red: 0.25, green: 0.47, blue: 0.85)  // royal blue
    case .neutral:
      return scheme == .dark
      ? Color(red: 0.66, green: 0.66, blue: 0.70)  // lighter stone gray
      : Color(red: 0.56, green: 0.56, blue: 0.60)  // medium gray
    case .disgust:
      return scheme == .dark
      ? Color(red: 0.16, green: 0.55, blue: 0.32)  // dark forest green
      : Color(red: 0.20, green: 0.65, blue: 0.38)  // emerald
    case .angry:
      return scheme == .dark
      ? Color(red: 0.75, green: 0.20, blue: 0.20)  // darker crimson
      : Color(red: 0.85, green: 0.26, blue: 0.26)  // strong red
    case .surprise:
      return scheme == .dark
      ? Color(red: 0.85, green: 0.45, blue: 0.18)  // deeper amber
      : Color(red: 0.95, green: 0.55, blue: 0.20)  // vibrant orange
    case .fear:
      return scheme == .dark
      ? Color(red: 0.38, green: 0.25, blue: 0.55)  // midnight violet
      : Color(red: 0.48, green: 0.32, blue: 0.66)  // royal violet
    }
  }
}
