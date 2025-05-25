import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Create the services in the correct dependency order
        let authService = SquareAuthService()
        let catalogService = SquareCatalogService(authService: authService)
        let readerService = SquareReaderService(authService: authService)
        let paymentService = SquarePaymentService(authService: authService, catalogService: catalogService)
        
        // Connect the reader service to the payment service
        paymentService.setReaderService(readerService)
        
        // Create the SwiftUI view that provides the window contents
        let contentView = ContentView()
            .environmentObject(DonationViewModel())
            .environmentObject(OrganizationStore())
            .environmentObject(KioskStore())
            .environmentObject(authService)
            .environmentObject(catalogService)
            .environmentObject(paymentService)
            .environmentObject(readerService)

        // Use a UIHostingController as window root view controller
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
        
        // Handle any URLs that were passed at launch
        if let urlContext = connectionOptions.urlContexts.first {
            self.scene(scene, openURLContexts: [urlContext])
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle URL scheme callbacks (e.g., for Square OAuth)
        if let url = URLContexts.first?.url, url.scheme == "charitypad" {
            print("SceneDelegate received URL: \(url)")
            
            // Check if this is the oauth-complete callback
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
            } else {
                // For other URLs, just post the notification with the URL
                NotificationCenter.default.post(name: .squareOAuthCallback, object: url)
            }
        }
    }
}
