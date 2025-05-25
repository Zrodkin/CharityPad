import SwiftUI
import SafariServices

struct SquareAuthorizationView: View {
    @EnvironmentObject private var squareAuthService: SquareAuthService
    @State private var showingSafari = false
    @State private var authURL: URL? = nil
    @State private var isPolling = false
    @State private var pollingTimer: Timer? = nil
    @State private var safariDismissed = false
    @State private var notificationObserver: NSObjectProtocol? = nil
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
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .squareOAuthCallback,
                object: nil,
                queue: .main
            ) { notification in
                print("Received OAuth callback notification")
                
                // Handle the OAuth callback
                handleOAuthCallback(notification)
                
                // Close the Safari view if it's open
                if self.showingSafari {
                    self.showingSafari = false
                    self.safariDismissed = true
                }
            }
        }
        // Sheet for Safari view
        .sheet(isPresented: $showingSafari, onDismiss: {
            // When Safari is dismissed normally (without notification)
            if !squareAuthService.isAuthenticated {
                safariDismissed = true
                isPolling = true
                print("Safari sheet dismissed normally, starting intensive polling")
                
                // Start intensive polling
                if squareAuthService.pendingAuthState != nil {
                    print("Found pending auth state: \(squareAuthService.pendingAuthState!)")
                    // Start polling with shorter interval for better responsiveness
                    startIntensivePolling()
                } else {
                    print("WARNING: No pending auth state found after Safari dismissed!")
                    squareAuthService.authError = "Authorization failed: No state parameter"
                }
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
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
                notificationObserver = nil
            }
        }
        // Monitor authentication state changes
        .onReceive(squareAuthService.$isAuthenticated) { isAuthenticated in
            if isAuthenticated {
                print("Authentication successful")
                hasCompletedOnboarding = true
                safariDismissed = false
                
                // Give user time to see success message
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
    
    // New function to handle OAuth callback notifications
    private func handleOAuthCallback(_ notification: Notification) {
        // If we received a notification with userInfo containing success/error
        if let userInfo = notification.userInfo,
           let success = userInfo["success"] as? Bool {
            print("OAuth callback received with success: \(success)")
            
            // If authentication was successful, stop polling and check authentication
            if success {
                pollingTimer?.invalidate()
                pollingTimer = nil
                
                // Use the checkAuthentication method to update the service state
                squareAuthService.checkAuthentication()
            } else {
                // Handle failure
                if let error = userInfo["error"] as? String {
                    squareAuthService.authError = "Authorization failed: \(error)"
                } else {
                    squareAuthService.authError = "Authorization failed"
                }
                
                // Stop authenticating state
                squareAuthService.isAuthenticating = false
            }
        }
        // If we received the notification with a URL object
        else if let url = notification.object as? URL {
            print("Received OAuth callback with URL: \(url)")
            
            // Try to extract success from URL components
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let successItem = components.queryItems?.first(where: { $0.name == "success" }),
               let successValue = successItem.value {
                let success = successValue == "true"
                
                // Handle success or failure
                if success {
                    // Success case - stop polling and check authentication
                    pollingTimer?.invalidate()
                    pollingTimer = nil
                    squareAuthService.checkAuthentication()
                } else {
                    // Failure case
                    let error = components.queryItems?.first(where: { $0.name == "error" })?.value
                    squareAuthService.authError = "Authorization failed: \(error ?? "Unknown error")"
                    squareAuthService.isAuthenticating = false
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
        
        // Set a timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
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
