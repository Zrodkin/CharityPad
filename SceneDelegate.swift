//
//  SceneDelegate.swift
//  CharityPadWSquare
//
//  Created by Wilkes Shluchim on 5/15/25.
//
import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Create the SwiftUI view that provides the window contents
        let contentView = ContentView()
            .environmentObject(DonationViewModel())
            .environmentObject(OrganizationStore())
            .environmentObject(KioskStore())
            .environmentObject(SquareAuthService())
            .environmentObject(SquarePaymentService(authService: SquareAuthService()))

        // Use a UIHostingController as window root view controller
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle URL scheme callbacks (e.g., for Square OAuth)
        if let url = URLContexts.first?.url, url.scheme == "charitypad" {
            NotificationCenter.default.post(name: .squareOAuthCallback, object: url)
        }
    }
}

