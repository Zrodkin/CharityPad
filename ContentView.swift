import SwiftUI

struct ContentView: View {
    // Add a state variable to force refreshes
    @State private var refreshTrigger = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("isInAdminMode") private var isInAdminMode: Bool = true
    @EnvironmentObject private var donationViewModel: DonationViewModel
    @EnvironmentObject private var organizationStore: OrganizationStore
    @EnvironmentObject private var kioskStore: KioskStore
    @EnvironmentObject private var squareAuthService: SquareAuthService
    @EnvironmentObject private var squarePaymentService: SquarePaymentService
    
    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(organizationStore)
                    .environmentObject(kioskStore)
                    .environmentObject(donationViewModel)
                    .environmentObject(squareAuthService)
                    // Add reset logic when showing OnboardingView
                    .onAppear {
                        // Reset any other state when showing onboarding
                        resetAppState()
                    }
            } else if isInAdminMode {
                AdminDashboardView()
                    .environmentObject(organizationStore)
                    .environmentObject(kioskStore)
                    .environmentObject(donationViewModel)
                    .environmentObject(squareAuthService)
            } else {
                HomeView()
                    .environmentObject(donationViewModel)
                    .environmentObject(kioskStore)
                    .environmentObject(squareAuthService)
            }
        }
        // Add this to force UI refresh when needed
        .id("main-content-\(refreshTrigger)")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ForceViewRefresh"))) { _ in
            // Force view refresh by toggling the trigger
            refreshTrigger.toggle()
        }
        .onAppear {
            // Ensure we default to admin mode when app starts
            if hasCompletedOnboarding {
                isInAdminMode = true
            }
            
            // Check if we're authenticated with Square
            squareAuthService.checkAuthentication()
            
            // Initialize the SDK if we're already authenticated
            if squareAuthService.isAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    squarePaymentService.initializeSDK()
                }
            }
        }
        // Add listener for authentication state changes
        .onChange(of: squareAuthService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // Initialize the SDK when authentication state changes to authenticated
                squarePaymentService.initializeSDK()
            }
        }
    }
    
    // Add a function to reset app state when needed
    private func resetAppState() {
        // Reset any in-memory state that might be causing issues
        // This runs when returning to onboarding/login screen
        squareAuthService.authError = nil
        squareAuthService.isAuthenticating = false
        
        // Reset donation state
        donationViewModel.resetDonation()
        
        // Ensure in-memory state is clean for a fresh start
        print("App state reset for fresh onboarding")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DonationViewModel())
            .environmentObject(OrganizationStore())
            .environmentObject(KioskStore())
            .environmentObject(SquareAuthService())
            .environmentObject(SquarePaymentService(authService: SquareAuthService()))
    }
}
