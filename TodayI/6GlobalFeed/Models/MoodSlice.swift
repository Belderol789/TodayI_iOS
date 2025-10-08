//
//  MoodSlice.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/20/25.
//

import SwiftUI

// MARK: - Slice Model
struct MoodSlice: Identifiable, Equatable {
  let id = UUID()
  let mood: Mood
  let count: Int
  var label: String { "\(mood)" }
}
