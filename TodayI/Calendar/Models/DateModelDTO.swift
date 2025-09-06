import Foundation
import SwiftData

struct DateModelDTO: Codable {
  let date: Date           // normalized (start-of-day, UTC)
  let moods: [String]      // store Mood.rawValue directly
}

extension DateModelDTO {
  init(from model: DateModel) {
    self.date = model.date
    self.moods = model.moodRaws   // already String
  }
}

extension DateModel {
  static func fromDTO(_ dto: DateModelDTO, in context: ModelContext) -> DateModel {
    let m = DateModel(
      date: dto.date,
      moods: dto.moods.compactMap(Mood.init(rawValue:))
    )
    context.insert(m)
    return m
  }
}
