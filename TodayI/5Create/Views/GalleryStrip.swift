//
//  GalleryStrip.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/13/25.
//

import SwiftUI

struct GalleryStrip: View {
  let images: [UIImage]
  var onRemove: (Int) -> Void
  
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(Array(images.enumerated()), id: \.offset) { (idx, img) in
          ZStack(alignment: .topTrailing) {
            Image(uiImage: img)
              .resizable()
              .scaledToFill()
              .frame(width: 110, height: 110)
              .clipped()
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            Button {
              onRemove(idx)
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.35))
                .padding(4)
            }
          }
        }
      }
      .padding(.vertical, 4)
    }
  }
}
