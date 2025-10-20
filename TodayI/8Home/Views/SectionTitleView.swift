import SwiftUI

struct SectionTitleView: View {
  let title: String
  let systemImage: String?   // optional icon name
  
  var body: some View {
    HStack(spacing: 8) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(.title3)
      }
      
      Text(title)
        .font(.title3).bold()
      
      Spacer()
    }
    .padding(.horizontal)
    .padding(.top, 8)
  }
}
