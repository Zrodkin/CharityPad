import SwiftUI
import SquareMobilePaymentsSDK

@main
struct DonationPadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    print("App received URL: \(url)")
                    // Let AppDelegate handle URL callbacks
                }
        }
    }
}
