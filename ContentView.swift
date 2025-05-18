import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("isInAdminMode") private var isInAdminMode: Bool = true
    @EnvironmentObject private var donationViewModel: DonationViewModel
    @EnvironmentObject private var organizationStore: OrganizationStore
    @EnvironmentObject private var kioskStore: KioskStore
    
    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(organizationStore)
                    .environmentObject(kioskStore)
                    .environmentObject(donationViewModel)
            } else if isInAdminMode {
                AdminDashboardView()
                    .environmentObject(organizationStore)
                    .environmentObject(kioskStore)
                    .environmentObject(donationViewModel)
            } else {
                HomeView()
                    .environmentObject(donationViewModel)
                    .environmentObject(kioskStore)
            }
        }
        .onAppear {
            // Ensure we default to admin mode when app starts
            if hasCompletedOnboarding {
                isInAdminMode = true
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DonationViewModel())
            .environmentObject(OrganizationStore())
            .environmentObject(KioskStore())
    }
}
