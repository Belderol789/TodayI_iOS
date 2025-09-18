//
//  LoggerManager.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/18/25.
//

import Foundation

public final class LoggerManager {
  
  static let instance = LoggerManager()
  
  func logFirebaseCall(function: String = #function) {
    print("$$$ Called firebase at \(function)")
  }
  
}
