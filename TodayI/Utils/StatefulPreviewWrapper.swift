//
//  StatefulPreviewWrapper.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/6/25.
//

import SwiftUI

struct StatefulPreviewWrapper<Value, Content: View>: View {
  @State var value: Value
  var content: (Binding<Value>) -> Content
  
  init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
    _value = State(initialValue: value)
    self.content = content
  }
  
  var body: some View {
    content($value)
  }
}

