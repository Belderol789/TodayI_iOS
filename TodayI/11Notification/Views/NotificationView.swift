import FirebaseAuth
import SwiftUI

struct NotificationView: View {
  @EnvironmentObject private var auth: AuthStore
  
  var body: some View {
    Group {
      if auth.isGuest {
        AuthRequiredView {
          // later: present SignUpView() or upgrade flow
        }
      } else {
        // user is logged in with email, Apple, Google, etc.
        EmptyView()
      }
    }
  }
}
