//
//  PickedMovie.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/14/25.
//

import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable

struct PickedMovie: Transferable {
  let url: URL
  
  static var transferRepresentation: some TransferRepresentation {
    // Ask the picker for a movie file and copy it into our temp location.
    FileRepresentation(importedContentType: .movie) { received in
      let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
      // Keep original extension if present; default to .mov
      let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
      let tmp = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
      try FileManager.default.copyItem(at: received.file, to: tmp)
      return Self(url: tmp)
    }
  }
}
