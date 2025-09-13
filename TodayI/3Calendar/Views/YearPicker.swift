import SwiftUI

struct YearPicker: View {
  @Binding var selectedYear: Int
  private let span = -3...3
  
  var body: some View {
    let current = Calendar.current.component(.year, from: Date())
    ForEach(span, id: \.self) { offset in
      let y = current + offset
      Button {
        selectedYear = y
      } label: {
        HStack {
          Text(y, format: .number.grouping(.never))
          if y == selectedYear { Image(systemName: "checkmark") }
        }
      }
    }
  }
}
