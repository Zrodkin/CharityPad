import SwiftUI

struct AdminDashboardView: View {
    @State private var selectedTab: String? = "home"
    @State private var showingKiosk = false
    @State private var showLogoutAlert = false
    @AppStorage("isInAdminMode") private var isInAdminMode: Bool = true
    @EnvironmentObject private var organizationStore: OrganizationStore
    @EnvironmentObject private var kioskStore: KioskStore
    @EnvironmentObject private var donationViewModel: DonationViewModel
    @EnvironmentObject private var squareAuthService: SquareAuthService
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack {
                List(selection: $selectedTab) {
                    Text(organizationStore.name)
                        .font(.headline)
                        .padding(.vertical, 8)
                        .tag(nil as String?)
                    
                    NavigationLink(value: "home") {
                        Label("Home Page", systemImage: "house")
                    }
                    
                    NavigationLink(value: "presetAmounts") {
                        Label("Preset Amounts", systemImage: "dollarsign.circle")
                    }
                    
                    NavigationLink(value: "receipts") {
                        Label("Email Receipts", systemImage: "envelope")
                    }
                    
                    NavigationLink(value: "timeout") {
                        Label("Timeout Settings", systemImage: "clock")
                    }
                    
                    Spacer()
                        .frame(height: 20)
                        .tag(nil as String?)
                    
                    Button(action: {
                        showLogoutAlert = true
                    }) {
                        Label("Logout", systemImage: "arrow.right.square")
                            .foregroundColor(.red)
                    }
                    .tag(nil as String?)
                }
                .listStyle(SidebarListStyle())
                
                // Square connection status
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Circle()
                            .fill(squareAuthService.isAuthenticated ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        
                        Text(squareAuthService.isAuthenticated ? "Connected to Square" : "Not connected to Square")
                            .font(.caption)
                            .foregroundColor(squareAuthService.isAuthenticated ? .green : .red)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 5)
                
                // Launch Kiosk Button
                Button(action: {
                    // Update the DonationViewModel with current preset amounts
                    kioskStore.updateDonationViewModel(donationViewModel)
                    
                    // Launch kiosk mode
                    isInAdminMode = false
                }) {
                    Label("Launch Kiosk", systemImage: "play.circle")
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .padding(.horizontal)
                .background(Color.white.opacity(0.1))
                .disabled(!squareAuthService.isAuthenticated)
            }
            .navigationTitle("Admin Dashboard")
        } detail: {
            // Detail content based on selection
            if let selectedTab = selectedTab {
                switch selectedTab {
                case "home":
                    HomePageSettingsView()
                        .environmentObject(kioskStore)
                case "presetAmounts":
                    PresetAmountsView()
                        .environmentObject(kioskStore)
                case "receipts":
                    EmailReceiptsView()
                        .environmentObject(organizationStore)
                case "timeout":
                    TimeoutSettingsView()
                        .environmentObject(kioskStore)
                default:
                    Text("Select an option from the sidebar")
                        .font(.title)
                        .foregroundColor(.gray)
                }
            } else {
                Text("Select an option from the sidebar")
                    .font(.title)
                    .foregroundColor(.gray)
            }
        }
        .alert(isPresented: $showLogoutAlert) {
            Alert(
                title: Text("Are you sure you want to logout?"),
                message: Text("You will need to log back in to access the admin panel."),
                primaryButton: .destructive(Text("Logout")) {
                    // Reset onboarding flag to go back to login screen
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct AdminDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        AdminDashboardView()
            .environmentObject(OrganizationStore())
            .environmentObject(KioskStore())
            .environmentObject(DonationViewModel())
            .environmentObject(SquareAuthService())
    }
}
