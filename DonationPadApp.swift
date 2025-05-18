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
    @StateObject private var squareReaderService: SquareReaderService
    
    // Initialize all services in init()
    init() {
        // First create the auth service
        let authService = SquareAuthService()
        
        // Then create the payment service using that auth service
        let paymentService = SquarePaymentService(authService: authService)
        
        // Then create the reader service using that auth service
        let readerService = SquareReaderService(authService: authService)
        
        // Connect the reader service to the payment service
        paymentService.setReaderService(readerService)
        
        // Initialize the StateObjects with the created services
        _squareAuthService = StateObject(wrappedValue: authService)
        _squarePaymentService = StateObject(wrappedValue: paymentService)
        _squareReaderService = StateObject(wrappedValue: readerService)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(donationViewModel)
                .environmentObject(organizationStore)
                .environmentObject(kioskStore)
                .environmentObject(squareAuthService)
                .environmentObject(squarePaymentService)
                .environmentObject(squareReaderService)
                .onOpenURL { url in
                    print("App received URL: \(url)")
                    // Handle URL callbacks - commented out since we're using polling
                    //if url.scheme == "charitypad" && url.host == "callback" {
                    //    squareAuthService.handleOAuthCallback(url: url)
                    //}
                }
                .onAppear {
                    // Initialize the SDK if already authenticated
                    if squareAuthService.isAuthenticated {
                        squarePaymentService.initializeSDK()
                    }
                    
                    // Start monitoring for Square readers
                    squareReaderService.startMonitoring()
                }
        }
    }
}
