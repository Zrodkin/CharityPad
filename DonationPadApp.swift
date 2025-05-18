import SwiftUI

@main
struct DonationPadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Create StateObjects for all dependencies
    @StateObject private var donationViewModel = DonationViewModel()
    @StateObject private var organizationStore = OrganizationStore()
    @StateObject private var kioskStore = KioskStore()
    
    // Declare the services without initializing them directly
    @StateObject private var squareAuthService: SquareAuthService
    @StateObject private var squarePaymentService: SquarePaymentService
    
    // Initialize both services in init()
    init() {
        // First create the auth service
        let authService = SquareAuthService()
        
        // Then create the payment service using that auth service
        let paymentService = SquarePaymentService(authService: authService)
        
        // Initialize the StateObjects with the created services
        _squareAuthService = StateObject(wrappedValue: authService)
        _squarePaymentService = StateObject(wrappedValue: paymentService)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(donationViewModel)
                .environmentObject(organizationStore)
                .environmentObject(kioskStore)
                .environmentObject(squareAuthService)
                .environmentObject(squarePaymentService)
                .onOpenURL { url in
                    print("App received URL: \(url)")
                    // Handle URL callbacks - commented out since we're using polling
                    //if url.scheme == "charitypad" && url.host == "callback" {
                    //    squareAuthService.handleOAuthCallback(url: url)
                    //}
                }
        }
    }
}

