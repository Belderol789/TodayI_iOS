//
//  LocalImageView.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/14/25.
//

import SwiftUI

struct LocalImageView: View {
  let path: String
  
  var body: some View {
    Group {
      if FileManager.default.fileExists(atPath: path),
         let ui = UIImage(contentsOfFile: path) {
        // Direct path works
        Image(uiImage: ui)
          .resizable()
          .scaledToFill()
        
      } else if let ui = UIImage(contentsOfFile: URL(fileURLWithPath: path).path) {
        // Handles when you accidentally saved "file://..." string
        Image(uiImage: ui)
          .resizable()
          .scaledToFill()
        
      } else {
        // Debug fallback
        ZStack {
          Color.secondary.opacity(0.1)
          VStack {
            Image(systemName: "photo")
              .resizable()
              .scaledToFit()
              .padding(24)
              .foregroundStyle(.secondary)
          }
        }
        .onAppear {
          print("❌ LocalImageView failed for path:", path,
                "exists:", FileManager.default.fileExists(atPath: path))
        }
      }
    }
  }
}
