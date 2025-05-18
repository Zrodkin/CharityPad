import SwiftUI
import SafariServices

struct OnboardingView: View {
    @State private var isLoading = false
    @State private var showingSafari = false
    @State private var authURL: URL? = nil
    @State private var safariDismissed = false
    @State private var isPolling = false
    @State private var pollingTimer: Timer? = nil
    @State private var notificationObserver: NSObjectProtocol? = nil
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @EnvironmentObject private var organizationStore: OrganizationStore
    @EnvironmentObject private var squareAuthService: SquareAuthService
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.55, green: 0.47, blue: 0.84),
                    Color(red: 0.56, green: 0.71, blue: 1.0),
                    Color(red: 0.97, green: 0.76, blue: 0.63),
                    Color(red: 0.97, green: 0.42, blue: 0.42)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Content
            VStack(spacing: 0) {
                Spacer()
                
                // Logo
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.9))
                        .frame(width: 120, height: 120)
                    
                    if let logoImage = UIImage(named: "organization-image") {
                        Image(uiImage: logoImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 90, height: 90)
                            .clipShape(Circle())
                    } else {
                        Text("Logo")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 30)
                
                // Title and description
                Text("Welcome to CharityPad")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.black)
                
                Text("Your smarter, simpler way to collect donations with ease.")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 5)
                    .padding(.bottom, 40)
                
                // Features list
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(text: "Collect donations easily via Square")
                    FeatureRow(text: "Personalize your kiosk with your own branding")
                    FeatureRow(text: "See live donation reports and insights")
                    FeatureRow(text: "Automatically send thank-you emails to donors")
                }
                .padding(.bottom, 40)
                
                // Status view when checking connection
                if safariDismissed {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                            .padding()
                        
                        Text("Checking connection status...")
                            .font(.headline)
                            .foregroundColor(.black)
                    }
                    .padding(.vertical)
                } else {
                    // Connect button
                    Button(action: {
                        if squareAuthService.isAuthenticated {
                            // If already authenticated, complete onboarding immediately
                            hasCompletedOnboarding = true
                            print("Already authenticated, completing onboarding directly")
                        } else {
                            // Otherwise start the auth flow directly
                            isLoading = true
                            startAuth()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 10)
                                Text("Connecting...")
                            } else {
                                Image("square-logo")
                                   .resizable()
                                   .scaledToFit()
                                   .frame(height: 20)
                                   .accessibility(label: Text("Square logo"))
                                Text("Connect with Square to Get Started")
                                Image(systemName: "arrow.right")
                                    .padding(.leading, 5)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal)
                }
                
                Text("By continuing, you agree to connect your Square account to CharityPad.\nWe'll use this to process payments and manage your donations.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.top, 15)
                    .padding(.horizontal)
                
                Spacer()
                
                // Support link
                HStack {
                    Text("Need help?")
                        .foregroundColor(.black)
                    
                    Button("Contact support") {
                        // Open support URL or email
                        if let url = URL(string: "mailto:support@charitypad.com") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundColor(.green)
                }
                .font(.subheadline)
                .padding(.bottom, 20)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.white.opacity(0.85))
                    .shadow(radius: 10)
            )
            .padding(.horizontal, 40)
            .padding(.vertical, 60)
        }
        .sheet(isPresented: $showingSafari, onDismiss: {
            // Only handle dismiss manually if we haven't already received the OAuth callback
            if !squareAuthService.isAuthenticated {
                safariDismissed = true
                isPolling = true
                print("Safari sheet dismissed manually, starting intensive polling")
                
                // Start intensive polling
                if squareAuthService.pendingAuthState != nil {
                    print("Found pending auth state: \(squareAuthService.pendingAuthState!)")
                    // Start polling with shorter interval for better responsiveness
                    startIntensivePolling()
                } else {
                    print("WARNING: No pending auth state found after Safari dismissed!")
                    isLoading = false
                }
            }
        }) {
            if let url = authURL {
                // Show Safari directly with a custom coordinator to handle URL scheme callbacks
                SafariView(url: url, onDismiss: {
                    if !squareAuthService.isAuthenticated {
                        showingSafari = false
                    }
                })
            }
        }
        // Check authentication on appearance
        .onAppear {
            squareAuthService.checkAuthentication()
            
            // Set up notification observer for OAuth callback
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .squareOAuthCallback,
                object: nil,
                queue: .main
            ) { notification in
                print("OnboardingView: Received OAuth callback notification")
                
                // Handle the notification
                handleOAuthCallback(notification)
                
                // Close Safari view if open
                if showingSafari {
                    showingSafari = false
                }
            }
        }
        .onDisappear {
            // Clean up when view disappears
            pollingTimer?.invalidate()
            pollingTimer = nil
            
            // Remove notification observer
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
                notificationObserver = nil
            }
        }
        // Monitor authentication state changes
        .onReceive(squareAuthService.$isAuthenticated) { isAuthenticated in
            if isAuthenticated {
                print("Authentication state changed to true, setting hasCompletedOnboarding")
                hasCompletedOnboarding = true
                
                // Reset loading state in case it was active
                isLoading = false
                safariDismissed = false
                
                // Cancel any active polling
                pollingTimer?.invalidate()
                pollingTimer = nil
            }
        }
    }
    
    // Handle OAuth callback notification
    private func handleOAuthCallback(_ notification: Notification) {
        // Extract success/error from notification userInfo
        if let userInfo = notification.userInfo,
           let success = userInfo["success"] as? Bool {
            print("OAuth callback received with success: \(success)")
            
            if success {
                // Stop polling and check authentication
                pollingTimer?.invalidate()
                pollingTimer = nil
                
                // Reset state variables
                isLoading = false
                safariDismissed = false
                
                print("Safari should be automatically closed by SafariView")
                
                // Directly check authentication to update state
                squareAuthService.checkAuthentication()
            } else {
                // Handle error
                if let error = userInfo["error"] as? String {
                    print("OAuth error: \(error)")
                }
                
                // Reset state
                isLoading = false
                safariDismissed = false
            }
        }
        // If notification contains a URL object
        else if let url = notification.object as? URL {
            print("Received OAuth callback with URL: \(url)")
            
            // Process URL if needed
            // This might be needed if your AppDelegate/SceneDelegate is passing the raw URL
        }
    }
    
    // Function to start more intensive polling after Safari is dismissed
    private func startIntensivePolling() {
        // Cancel any existing timer
        pollingTimer?.invalidate()
        
        // Create a timer that checks status more frequently (every 0.5 seconds)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            squareAuthService.checkPendingAuthorization { success in
                if success {
                    print("Polling found successful authentication")
                    pollingTimer?.invalidate()
                    pollingTimer = nil
                    safariDismissed = false
                }
            }
        }
        
        // Also immediately check once
        squareAuthService.checkPendingAuthorization { _ in }
        
        // Set a timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            guard self.safariDismissed && !self.squareAuthService.isAuthenticated else { return }
            
            self.pollingTimer?.invalidate()
            self.pollingTimer = nil
            self.isLoading = false
            self.safariDismissed = false
            print("Polling timed out after 30 seconds")
        }
    }
    
    private func startAuth() {
        print("Starting Square OAuth flow directly...")
        
        // Get authorization URL from your backend
        SquareConfig.generateOAuthURL { url, error, state in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to generate authorization URL: \(error.localizedDescription)")
                    isLoading = false
                    return
                }
                
                guard let url = url else {
                    print("Failed to generate authorization URL")
                    isLoading = false
                    return
                }
                
                // Set state if available
                if let state = state {
                    print("Setting pendingAuthState to: \(state)")
                    squareAuthService.pendingAuthState = state
                } else {
                    print("WARNING: No state returned from generateOAuthURL")
                }
                
                // Store URL and update state
                self.authURL = url
                squareAuthService.isAuthenticating = true
                
                // Show Safari directly
                self.showingSafari = true
            }
        }
    }
}

// Add the FeatureRow struct back
struct FeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.black)
                .padding(.top, 2)
            
            Text(text)
                .foregroundColor(Color.gray.opacity(0.8))
        }
    }
}
