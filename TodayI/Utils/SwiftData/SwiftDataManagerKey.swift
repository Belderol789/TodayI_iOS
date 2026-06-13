//
//  SwiftDataManagerKey.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/14/25.
//

import Foundation
import SwiftUI

private struct SwiftDataManagerKey: EnvironmentKey {
  static let defaultValue: SwiftDataManager? = nil
}

extension EnvironmentValues {
  var swiftDataManager: SwiftDataManager? {
    get { self[SwiftDataManagerKey.self] }
    set { self[SwiftDataManagerKey.self] = newValue } // ← setter required
  }
}
