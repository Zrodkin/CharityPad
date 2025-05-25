import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        
        let safariViewController = SFSafariViewController(url: url, configuration: configuration)
        safariViewController.dismissButtonStyle = .close
        safariViewController.delegate = context.coordinator
        
        // Store reference to the safari view controller for dismissal
        context.coordinator.safariViewController = safariViewController
        
        return safariViewController
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // Nothing to update
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(self)
        
        // Add notification observer to handle OAuth callback and close this view
        coordinator.notificationObserver = NotificationCenter.default.addObserver(
            forName: .squareOAuthCallback,
            object: nil,
            queue: .main
        ) { [weak coordinator] _ in
            print("SafariView received OAuth callback notification")
            
            // Dismiss safari view controller when notification is received
            if let safariVC = coordinator?.safariViewController,
               safariVC.presentingViewController != nil {
                safariVC.dismiss(animated: true) {
                    // Call onDismiss after the safari view is dismissed
                    DispatchQueue.main.async {
                        coordinator?.parent.onDismiss()
                    }
                }
            } else {
                // If we can't access the safari view controller, still call onDismiss
                DispatchQueue.main.async {
                    coordinator?.parent.onDismiss()
                }
            }
        }
        
        return coordinator
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: SafariView
        var safariViewController: SFSafariViewController?
        var notificationObserver: NSObjectProtocol?
        
        init(_ parent: SafariView) {
            self.parent = parent
            super.init()
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            // User manually closed the safari view
            parent.onDismiss()
        }
        
        // Called when SafariViewController begins to load a URL
        func safariViewController(_ controller: SFSafariViewController, initialLoadDidRedirectTo URL: URL) {
            print("Safari redirected to: \(URL)")
            
            // If the URL is our custom scheme, handle it here
            if URL.scheme == "charitypad" {
                print("Detected redirect to our custom URL scheme: \(URL)")
                
                // Extract success parameter if available
                if let components = URLComponents(url: URL, resolvingAgainstBaseURL: false),
                   let successItem = components.queryItems?.first(where: { $0.name == "success" }),
                   let successValue = successItem.value {
                    
                    let success = successValue == "true"
                    let error = components.queryItems?.first(where: { $0.name == "error" })?.value
                    
                    // Post notification with success/error info
                    NotificationCenter.default.post(
                        name: .squareOAuthCallback,
                        object: nil,
                        userInfo: ["success": success, "error": error as Any]
                    )
                }
            }
        }
        
        deinit {
            // Clean up the notification observer
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
