import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var donationViewModel: DonationViewModel
    @EnvironmentObject private var kioskStore: KioskStore
    @State private var navigateToDonation = false
    @State private var isLongPressing = false
    @State private var longPressProgress: Double = 0.0
    @State private var longPressStartTime = Date()
    @State private var longPressTimer: Timer? = nil
    @State private var showGuidedAccessAlert = false
    @AppStorage("isInAdminMode") private var isInAdminMode: Bool = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                if kioskStore.homePageEnabled {
                    // Home page content when enabled
                    homePageContent
                } else {
                    // When home page is disabled, show DonationSelectionView
                    // but wrapped in a NavigationStack to prevent navigation issues
                    NavigationStack {
                        DonationSelectionView()
                            .onAppear {
                                // Reset donation state when starting
                                donationViewModel.resetDonation()
                            }
                    }
                    .edgesIgnoringSafeArea(.all)
                }
                
                // Exit kiosk mode overlay - always on top
                if isLongPressing {
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            VStack {
                                ProgressView(value: longPressProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                                    .frame(width: 200)
                                    .padding()
                                
                                Text("Hold to exit kiosk mode...")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                        )
                }
            }
            .contentShape(Rectangle()) // Make the entire view tappable
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 2.0)
                    .onEnded { _ in
                        // Start long press
                        isLongPressing = true
                        longPressStartTime = Date()
                        
                        // Cancel any existing timer
                        longPressTimer?.invalidate()
                        
                        // Start a new timer
                        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                            let elapsed = Date().timeIntervalSince(longPressStartTime)
                            longPressProgress = min(elapsed / 3.0, 1.0)
                            
                            // Check if we've reached the end
                            if elapsed >= 3.0 {
                                timer.invalidate()
                                longPressTimer = nil
                                
                                // Check if we're in guided access mode
                                if UIAccessibility.isGuidedAccessEnabled {
                                    showGuidedAccessAlert = true
                                } else {
                                    // Not in guided access, exit kiosk mode
                                    isInAdminMode = true
                                }
                            }
                        }
                    }
            )
            .onTapGesture {
                // Only navigate to donation if not in long press mode
                if !isLongPressing {
                    navigateToDonation = true
                }
            }
            .onAppear {
                // Reset donation state when returning to home
                donationViewModel.resetDonation()
                
                // Ensure any lingering long press state is reset
                resetLongPress()
            }
            .onDisappear {
                // Clean up when view disappears
                resetLongPress()
            }
            .navigationDestination(isPresented: $navigateToDonation) {
                DonationSelectionView()
            }
            .alert("Exit Kiosk Mode", isPresented: $showGuidedAccessAlert) {
                Button("Cancel", role: .cancel) {
                    resetLongPress()
                }
                Button("Exit", role: .destructive) {
                    // This won't actually exit guided access, but will show the intent
                    // The system will prompt for the guided access passcode
                    UIAccessibility.requestGuidedAccessSession(enabled: false) { success in
                        if success {
                            isInAdminMode = true
                        }
                        resetLongPress()
                    }
                }
            } message: {
                Text("This device is in Guided Access mode. You'll need to enter the Guided Access passcode to exit.")
            }
        }
        .id("homeNavigation") // Add an ID to the NavigationStack for consistent state
    }
    
    // Function to reset all long press state
    private func resetLongPress() {
        isLongPressing = false
        longPressProgress = 0.0
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
    
    // Extract home page content to a computed property for cleaner code
    private var homePageContent: some View {
        ZStack {
            // Background image
            if let backgroundImage = kioskStore.backgroundImage {
                Image(uiImage: backgroundImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Image("organization-image")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        if UIImage(named: "organization-image") == nil {
                            print("Warning: 'organization-image' not found in asset catalog.")
                        }
                    }
            }

            // Dark overlay
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)

            // Tap to donate text
            VStack {
                Text(kioskStore.headline)
                    .font(.system(size: 90, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 10)
                    .multilineTextAlignment(.center)
                
                if !kioskStore.subtext.isEmpty {
                    Text(kioskStore.subtext)
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                }
            }
            .offset(y: -20)
        }
        .contentShape(Rectangle())
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(DonationViewModel())
            .environmentObject(KioskStore())
    }
}
