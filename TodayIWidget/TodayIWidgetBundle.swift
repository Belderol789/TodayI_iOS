//
//  TodayIWidgetBundle.swift
//  TodayIWidget
//
//  Created by Kemuel Clyde Belderol on 9/25/26.
//

import WidgetKit
import SwiftUI

@main
struct TodayIWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayIWidget()
        TodayIWidgetControl()
        TodayIWidgetLiveActivity()
    }
}
