import SwiftUI
import SafariServices

struct SquareAuthorizationView: View {
    @EnvironmentObject private var squareAuthService: SquareAuthService
    @State private var showingSafari = false
    @State private var authURL: URL? = nil
    @State private var isPolling = false
    @State private var pollingTimer: Timer? = nil
    @State private var safariDismissed = false
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Square logo
            Image("square-logo-white")
                .resizable()
                .scaledToFit()
                .frame(height: 60)
                .padding(.top, 40)
            
            if safariDismissed {
                // Show checking status view after Safari is closed
                VStack(spacing: 16) {
                    Text("Checking connection status...")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    ProgressView()
                        .padding()
                    
                    Text("Please wait while we verify your Square connection.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if squareAuthService.isAuthenticated {
                // Show success view
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .padding()
                    
                    Text("Successfully connected to Square!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("You'll be redirected to the dashboard in a moment...")
                        .foregroundColor(.gray)
                }
                .onAppear {
                    // Set hasCompletedOnboarding to true
                    hasCompletedOnboarding = true
                    
                    // Auto-dismiss after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } else if let error = squareAuthService.authError {
                // Show error view
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                        .padding()
                    
                    Text("Connection Failed")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button(action: {
                        squareAuthService.authError = nil
                        safariDismissed = false
                        startAuth()
                    }) {
                        Text("Try Again")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
            } else if squareAuthService.isAuthenticating || showingSafari {
                // Show connecting view
                VStack(spacing: 16) {
                    Text("Connecting to Square")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    ProgressView()
                        .padding()
                    
                    Text(isPolling ? "Waiting for authorization..." : "Opening Square authorization page...")
                        .foregroundColor(.gray)
                }
            } else {
                // Show initial connect view
                VStack(spacing: 16) {
                    Text("Connect with Square")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("CharityPad needs to connect to your Square account to process payments.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(action: startAuth) {
                        HStack {
                            Image("square-logo-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            
                            Text("Connect with Square")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Check if we're already authenticated when the view appears
            if squareAuthService.isAuthenticated {
                print("Already authenticated, setting hasCompletedOnboarding and dismissing")
                hasCompletedOnboarding = true
                
                // Auto-dismiss if already authenticated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.presentationMode.wrappedValue.dismiss()
                }
            }
            
            // Set up notification observer for callbacks
            NotificationCenter.default.addObserver(
                forName: .squareOAuthCallback,
                object: nil,
                queue: .main
            ) { notification in
                if let url = notification.object as? URL {
                    print("Received OAuth callback notification with URL: \(url)")
                }
            }
        }
        // Sheet for Safari view
        .sheet(isPresented: $showingSafari, onDismiss: {
            // When Safari is dismissed
            safariDismissed = true
            isPolling = true
            print("Safari sheet dismissed, starting intensive polling")
            
            // Start intensive polling
            if squareAuthService.pendingAuthState != nil {
                print("Found pending auth state: \(squareAuthService.pendingAuthState!)")
                // Start polling with shorter interval for better responsiveness
                startIntensivePolling()
            } else {
                print("WARNING: No pending auth state found after Safari dismissed!")
                squareAuthService.authError = "Authorization failed: No state parameter"
            }
        }) {
            if let url = authURL {
                // Use SafariView
                SafariView(url: url, onDismiss: {
                    showingSafari = false
                })
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            pollingTimer?.invalidate()
            pollingTimer = nil
            
            // Remove observer
            NotificationCenter.default.removeObserver(self)
        }
        // Monitor authentication state changes
        .onReceive(squareAuthService.$isAuthenticated) { isAuthenticated in
            if isAuthenticated && safariDismissed {
                print("Authentication successful after Safari dismissed")
                hasCompletedOnboarding = true
                
                // Give user time to see success message
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
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
                }
            }
        }
        
        // Also immediately check once
        squareAuthService.checkPendingAuthorization { _ in }
        
        // Set a timeout - REMOVE [weak self] HERE
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            // Instead of using guard let self, just use self directly
            guard self.safariDismissed && !self.squareAuthService.isAuthenticated else { return }
            
            self.pollingTimer?.invalidate()
            self.pollingTimer = nil
            self.squareAuthService.authError = "Connection timed out. Please try again."
            print("Polling timed out after 30 seconds")
        }
    }
    
    private func startAuth() {
        print("Starting Square OAuth flow...")
        
        // Get authorization URL from your backend
        SquareConfig.generateOAuthURL { url, error, state in
            DispatchQueue.main.async {
                if let error = error {
                    squareAuthService.authError = "Failed to generate authorization URL: \(error.localizedDescription)"
                    return
                }
                
                guard let url = url else {
                    squareAuthService.authError = "Failed to generate authorization URL"
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
                safariDismissed = false
                
                // Show Safari
                self.showingSafari = true
            }
        }
    }
}
