//
//  TodayIApp.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/3/25.
//

import SwiftUI

@main
struct TodayIApp: App {
    var body: some Scene {
        WindowGroup {
          CalendarView()
        }
        .modelContainer(for: DateModel.self)
    }
}
