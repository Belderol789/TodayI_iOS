import SwiftUI

struct MonthThumbnail: View {
  let month: Date
  let models: [DateModel]
  @Environment(\.colorScheme) private var scheme
  
  private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
  private let cal = Calendar.current
  
  // Map each day -> Color (last mood wins if multiple)
  private var colorByDate: [Date: Color] {
    var dict: [Date: Color] = [:]
    for m in models {
      let key = cal.startOfDay(for: m.date)
      let color = m.moods.last?.adaptiveColor ?? .gray
      dict[key] = color
    }
    return dict
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(month, format: .dateTime.month(.abbreviated))
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
      
      LazyVGrid(columns: cols, spacing: 2) {
        ForEach(gridDates.indices, id: \.self) { i in
          let d = gridDates[i]
          let color = d.flatMap { colorByDate[$0.startOfDay] }
          
          Circle()
            .fill(color ?? Color.gray.opacity(0.15))  // ← mood color per day
            .frame(height: 6)
            .opacity(color == nil ? 0.6 : 1.0)
        }
      }
      .padding(.horizontal, 4)
      .padding(.bottom, 6)
    }
  }
  
  private var gridDates: [Date?] {
    let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
    let count = cal.range(of: .day, in: .month, for: start)!.count
    let first = cal.component(.weekday, from: start)
    let offset = (first - cal.firstWeekday + 7) % 7
    
    var arr = Array(repeating: nil as Date?, count: offset)
    for day in 0..<count {
      arr.append(cal.date(byAdding: .day, value: day, to: start)!)
    }
    let rem = arr.count % 7
    if rem != 0 { arr.append(contentsOf: Array(repeating: nil, count: 7 - rem)) }
    return arr
  }
}
