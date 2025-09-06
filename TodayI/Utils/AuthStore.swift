//
//  AuthStore.swift
//  TodayI
//
//  Created by Kemuel Clyde Belderol on 9/6/25.
//

import Foundation

final class AuthStore: ObservableObject {
  @Published var userID: String? = "debug-user"   // set this after sign-in
  @Published var username: String? = "tester"
}
