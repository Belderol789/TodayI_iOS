//
//  SingleImagePreview.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/13/25.
//

import SwiftUI

struct SingleImagePreview: View {
  let image: UIImage
  var onClear: () -> Void
  
  var body: some View {
    ZStack(alignment: .topTrailing) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(height: 180)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      
      Button(action: onClear) {
        Image(systemName: "xmark.circle.fill")
          .font(.title2)
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, .black.opacity(0.35))
          .padding(8)
      }
    }
  }
}
