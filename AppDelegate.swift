import UIKit
import SwiftUI
import SquareMobilePaymentsSDK

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Initialize the Square Mobile Payments SDK
        // This must be done before any calls to MobilePaymentsSDK.shared
        
        // Using the client ID directly since it's defined as a non-optional String in SquareConfig
        let applicationId = SquareConfig.clientID
        
        MobilePaymentsSDK.initialize(squareApplicationID: applicationId)
        
        // Print success message for debugging
        print("Square Mobile Payments SDK initialized successfully")
        
        return true
    }
  
    // Update the application(_:open:options:) method to handle the callback from our backend
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("AppDelegate received URL: \(url)")

        // Handle Square OAuth callback via custom URL scheme
        if url.scheme == "charitypad" {
            print("Received callback with URL: \(url)")
            
            // Check if this is our oauth-complete callback
            if url.host == "oauth-complete" {
                // Extract success parameter
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let success = components?.queryItems?.first(where: { $0.name == "success" })?.value == "true"
                let error = components?.queryItems?.first(where: { $0.name == "error" })?.value
                
                // Post notification with success/error info
                NotificationCenter.default.post(
                    name: .squareOAuthCallback,
                    object: nil,
                    userInfo: ["success": success, "error": error as Any]
                )
                
                print("OAuth flow completed with success: \(success)")
                return true
            }
            
            // For other charitypad:// URLs, just post the notification with the URL
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
  static let squareAuthenticationSuccessful = Notification.Name("SquareAuthenticationSuccessful")
}
