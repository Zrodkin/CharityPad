
import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("isInAdminMode") private var isInAdminMode: Bool = true
    @EnvironmentObject private var donationViewModel: DonationViewModel
    @EnvironmentObject private var organizationStore: OrganizationStore
    @EnvironmentObject private var kioskStore: KioskStore
    @EnvironmentObject private var squareAuthService: SquareAuthService
    
    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(organizationStore)
                    .environmentObject(kioskStore)
                    .environmentObject(donationViewModel)
                    .environmentObject(squareAuthService)
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
        .onAppear {
            // Ensure we default to admin mode when app starts
            if hasCompletedOnboarding {
                isInAdminMode = true
            }
            
            // Check if we're authenticated with Square
            squareAuthService.checkAuthentication()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DonationViewModel())
            .environmentObject(OrganizationStore())
            .environmentObject(KioskStore())
            .environmentObject(SquareAuthService())
    }
}
