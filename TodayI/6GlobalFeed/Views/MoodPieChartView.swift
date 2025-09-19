import SwiftUI
import Charts

struct MoodPieChart: View {
  let slices: [MoodSlice]
  let total: Int
  @Binding var tabSelection: AppTab    // 👈 add this
  
  var dominant: MoodSlice? { slices.max(by: { $0.count < $1.count }) }
  
  var body: some View {
    VStack(spacing: 8) {
      Text("Today the world feels")
        .font(.title3).fontWeight(.semibold)
        .multilineTextAlignment(.center)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .center)
      
      ZStack {
        if total != 0 {
          // EMPTY STATE
          VStack(spacing: 12) {
            Image(systemName: "face.smiling")
              .resizable().scaledToFit()
              .frame(width: 44, height: 44)
              .foregroundStyle(.secondary)
            
            Text("Be the world's first mood today!")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            
            Button {
              tabSelection = .create     // 👈 switch tab
            } label: {
              Text("Create a Memory")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 240)
        } else {
          // CHART + dominant mood as before…
          Chart(slices) { slice in
            SectorMark(
              angle: .value("Count", slice.count),
              innerRadius: .ratio(0.55),
              outerRadius: .inset(0)
            )
            .foregroundStyle(slice.mood.adaptiveColor)
            .annotation(position: .overlay, alignment: .center) {
              let pct = Double(slice.count) / Double(max(total, 1))
              if pct >= 0.07 {
                Text("\(Int(round(pct * 100)))%")
                  .font(.caption2).bold()
                  .foregroundStyle(.white)
              }
            }
          }
          .chartLegend(position: .bottom, alignment: .center)
          .frame(maxWidth: .infinity, minHeight: 240)
          
          if let topCount = slices.map(\.count).max(), topCount > 0 {
            let tops = slices.filter { $0.count == topCount }
            HStack(alignment: .center, spacing: -8) {
              ForEach(tops) { top in
                VStack(spacing: 4) {
                  top.mood.image
                    .resizable().scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(top.mood.adaptiveColor)
                  Text("\(topCount)")
                    .font(.headline).bold()
                    .foregroundStyle(.primary)
                }
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }
}
