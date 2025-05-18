import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
      return true
  }
  
  // Update the application(_:open:options:) method to handle the callback from our backend
  func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
      print("AppDelegate received URL: \(url)")

      // We're using the server-side polling approach, so direct callbacks are not expected
      // If you uncomment this code, it will interfere with the server polling approach
      
      /*
      // Handle Square OAuth callback
      if url.scheme == "charitypad" && url.host == "callback" {
          // ... direct callback code ...
      }
      */
      
      // Still post the notification for backward compatibility
      if url.scheme == "charitypad" {
          print("Received callback with URL: \(url)")
          NotificationCenter.default.post(
              name: .squareOAuthCallback,
              object: url
          )
          return true
      }
      
      print("URL not handled: \(url)")
      return false
  }
}

// Add a notification name for the OAuth callback
extension Notification.Name {
  static let squareOAuthCallback = Notification.Name("SquareOAuthCallback")
}
