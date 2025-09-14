//
//  MediaSection.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/14/25.
//

import SwiftUI

struct MediaSection: View {
  let images: [PickedImage]
  var onRemove: (UUID) -> Void
  
  var body: some View {
    if images.count == 1, let item = images.first {
      ZStack(alignment: .topTrailing) {
        Image(uiImage: item.image)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        
        removeButton(id: item.id)
      }
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(images) { item in
            ZStack(alignment: .topTrailing) {
              Image(uiImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              
              removeButton(id: item.id)
            }
          }
        }
        .frame(height: 160)
      }
    }
  }
  
  @ViewBuilder
  private func removeButton(id: UUID) -> some View {
    Button {
      onRemove(id)
    } label: {
      Image(systemName: "xmark.circle.fill")
        .font(.title3)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.primary)
        .padding(6)
        .background(.thinMaterial, in: Circle())
    }
    .buttonStyle(.plain)
    .padding(8)
  }
}
