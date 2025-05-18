import SwiftUI
import SafariServices

struct SquareAuthorizationView: View {
    @EnvironmentObject private var squareAuthService: SquareAuthService
    @State private var showingSafari = false
    @State private var authURL: URL? = nil
    @State private var isPolling = false
    @State private var pollingTimer: Timer? = nil
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            // Square logo
            Image("square-logo-white")
                .resizable()
                .scaledToFit()
                .frame(height: 60)
                .padding(.top, 40)
            
            Text("Connect with Square")
                .font(.title)
                .fontWeight(.bold)
            
            Text("CharityPad needs to connect to your Square account to process payments.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if squareAuthService.isAuthenticating {
                ProgressView()
                    .padding()
                
                Text(isPolling ? "Waiting for authorization..." : "Opening Square authorization page...")
                    .foregroundColor(.gray)
            } else if let error = squareAuthService.authError {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                
                Button(action: {
                    squareAuthService.authError = nil
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
            } else if squareAuthService.isAuthenticated {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                    .padding()
                
                Text("Successfully connected to Square!")
                    .fontWeight(.semibold)
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            } else {
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
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Check if we're already authenticated
            squareAuthService.checkAuthentication()
            
            // Listen for OAuth callback notifications
            NotificationCenter.default.addObserver(
                forName: .squareOAuthCallback,
                object: nil,
                queue: .main
            ) { notification in
                if let url = notification.object as? URL {
                    print("Received OAuth callback notification with URL: \(url)")
                    // We're using polling, so we don't need to handle the URL directly
                    // Just log it for debugging purposes
                }
            }
        }
        // Replace background with sheet for better modal presentation
        .sheet(isPresented: $showingSafari, onDismiss: {
            // Start polling when Safari is dismissed
            isPolling = true
            print("Safari sheet dismissed, starting polling")
            // This can trigger polling if not already started
            if squareAuthService.pendingAuthState != nil {
                squareAuthService.startPollingForAuthStatus()
            }
        }) {
            if let url = authURL {
                // Use your existing SafariView here
                SafariView(url: url, onDismiss: {
                    showingSafari = false
                })
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            pollingTimer?.invalidate()
            pollingTimer = nil
            
            // Remove the observer when the view disappears
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    private func startAuth() {
        print("Starting Square OAuth flow...")
        
        // Get authorization URL from your backend
        SquareConfig.generateOAuthURL { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    squareAuthService.authError = "Failed to generate authorization URL: \(error.localizedDescription)"
                    return
                }
                
                guard let url = url else {
                    squareAuthService.authError = "Failed to generate authorization URL"
                    return
                }
                
                // Store the URL and show the Safari view
                self.authURL = url
                squareAuthService.startOAuthFlow()
                
                // Present the Safari view as a sheet
                self.showingSafari = true
            }
        }
    }
}
