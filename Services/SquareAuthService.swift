import Foundation
import SwiftUI

class SquareAuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var authError: String? = nil
    
    // Store tokens in UserDefaults (in a real app, use Keychain for better security)
    private let accessTokenKey = "squareAccessToken"
    private let refreshTokenKey = "squareRefreshToken"
    private let merchantIdKey = "squareMerchantId"
    private let expirationDateKey = "squareTokenExpirationDate"
    private let pendingAuthStateKey = "squarePendingAuthState"
    
    var accessToken: String? {
        get { UserDefaults.standard.string(forKey: accessTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: accessTokenKey) }
    }
    
    var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: refreshTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: refreshTokenKey) }
    }
    
    var merchantId: String? {
        get { UserDefaults.standard.string(forKey: merchantIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: merchantIdKey) }
    }
    
    var tokenExpirationDate: Date? {
        get { UserDefaults.standard.object(forKey: expirationDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: expirationDateKey) }
    }
    
    var pendingAuthState: String? {
        get { UserDefaults.standard.string(forKey: pendingAuthStateKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingAuthStateKey) }
    }
    
    init() {
        // Check if we have a valid token
        checkAuthentication()
    }
    
    // Replace the checkAuthentication method
    func checkAuthentication() {
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)\(SquareConfig.statusEndpoint)?organization_id=\(SquareConfig.organizationId)") else {
            isAuthenticated = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("Error checking authentication: \(error)")
                    self.isAuthenticated = false
                    return
                }
                
                guard let data = data else {
                    self.isAuthenticated = false
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let connected = json["connected"] as? Bool {
                            self.isAuthenticated = connected
                            
                            // If token needs refresh, trigger refresh
                            if let needsRefresh = json["needs_refresh"] as? Bool, needsRefresh {
                                self.refreshAccessToken()
                            }
                        } else {
                            self.isAuthenticated = false
                        }
                    } else {
                        self.isAuthenticated = false
                    }
                } catch {
                    print("Error parsing authentication response: \(error)")
                    self.isAuthenticated = false
                }
            }
        }.resume()
    }
    
    // Update the startOAuthFlow method
    func startOAuthFlow() {
        isAuthenticating = true
        authError = nil
        
        // Generate a state parameter and store it
        let state = UUID().uuidString
        pendingAuthState = state
        
        print("Starting OAuth flow with state: \(state)")
        
        SquareConfig.generateOAuthURL { [weak self] url, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("Failed to generate authorization URL: \(error.localizedDescription)")
                    self.authError = "Failed to generate authorization URL: \(error.localizedDescription)"
                    self.isAuthenticating = false
                    return
                }
                
                guard let url = url else {
                    self.authError = "Failed to generate authorization URL: No URL returned"
                    self.isAuthenticating = false
                    return
                }
                
                print("Starting OAuth flow with URL: \(url)")
                self.openAuthURL(url)
                
                // Start polling after opening the URL
                self.startPollingForAuthStatus()
            }
        }
    }
    
    // Update the checkPendingAuthorization method to use the correct URL format
    func checkPendingAuthorization(completion: @escaping (Bool) -> Void) {
        guard isAuthenticating, !isAuthenticated, let state = pendingAuthState else {
            completion(isAuthenticated)
            return
        }
        
        // Check with our backend if the authorization has been completed
        guard let backendURL = URL(string: "\(SquareConfig.backendBaseURL)\(SquareConfig.statusEndpoint)?state=\(state)") else {
            authError = "Invalid backend URL"
            isAuthenticating = false
            completion(false)
            return
        }
        
        print("Checking authorization status with backend: \(backendURL)")
        
        var request = URLRequest(url: backendURL)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.authError = "Network error: \(error.localizedDescription)"
                    print("Network error checking auth status: \(error)")
                    completion(false)
                    return
                }
                
                // Print HTTP status code for debugging
                if let httpResponse = response as? HTTPURLResponse {
                    print("Backend status code: \(httpResponse.statusCode)")
                }
                
                guard let data = data else {
                    self.authError = "No data received from backend"
                    print("No data received from backend")
                    completion(false)
                    return
                }
                
                // Print raw response for debugging
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                print("Backend response: \(responseString)")
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check if we have a valid token
                        if let isConnected = json["connected"] as? Bool, isConnected,
                           let accessToken = json["access_token"] as? String,
                           let refreshToken = json["refresh_token"] as? String,
                           let merchantId = json["merchant_id"] as? String,
                           let expiresAt = json["expires_at"] as? String {
                    
                        // Store tokens
                        self.accessToken = accessToken
                        self.refreshToken = refreshToken
                        self.merchantId = merchantId
                    
                        // Parse expiration date
                        let dateFormatter = ISO8601DateFormatter()
                        if let expirationDate = dateFormatter.date(from: expiresAt) {
                            self.tokenExpirationDate = expirationDate
                            print("Token expires at: \(expirationDate)")
                        } else {
                            // If we can't parse the date, set it to 30 days from now
                            self.tokenExpirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)
                            print("Could not parse expiration date, set to 30 days from now")
                        }
                    
                        self.pendingAuthState = nil
                        self.isAuthenticated = true
                        self.isAuthenticating = false
                    
                        print("Square authentication successful!")
                        completion(true)
                        return
                    } else if let error = json["error"] as? String {
                        if error == "token_not_found" {
                            // This is normal if the user hasn't completed auth yet
                            print("Token not found yet, waiting for user to complete authorization")
                            completion(false)
                            return
                        } else {
                            self.authError = "Backend error: \(error)"
                            self.isAuthenticating = false
                            print("Backend error: \(error)")
                            completion(false)
                            return
                        }
                    } else if let message = json["message"] as? String, message == "token_not_found" {
                        // This is normal if the user hasn't completed auth yet
                        print("Token not found yet, waiting for user to complete authorization")
                        completion(false)
                        return
                    }
                }
        
                // If we get here, we're still waiting for the user to complete authorization
                print("Still waiting for authorization to complete")
                completion(false)
            
            } catch {
                self.authError = "Failed to parse response: \(error.localizedDescription)"
                self.isAuthenticating = false
                print("JSON parsing error: \(error)")
                completion(false)
            }
        }
    }.resume()
}
    
   
    
    // Add a method to handle the OAuth callback URL
    func handleOAuthCallback(url: URL) {
        print("Processing OAuth callback: \(url)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            authError = "Invalid callback URL structure"
            isAuthenticating = false
            print("Error: Invalid callback URL structure")
            return
        }
        
        // Check for success parameter from our backend
        if let success = queryItems.first(where: { $0.name == "success" })?.value,
           success == "true",
           let merchantId = queryItems.first(where: { $0.name == "merchant_id" })?.value {
            
            print("Received successful callback with merchant ID: \(merchantId)")
            
            // Start polling for authentication status
            startPollingForAuthStatus(merchantId: merchantId)
        } else if let error = queryItems.first(where: { $0.name == "error" })?.value {
            authError = "Authorization failed: \(error)"
            isAuthenticating = false
            print("Square OAuth Error: \(error)")
        } else {
            // If we don't have a success parameter, start polling anyway
            print("Callback received without explicit success parameter, starting polling")
            startPollingForAuthStatus()
        }
    }

    // Add this new method for polling
func startPollingForAuthStatus(merchantId: String? = nil) {
        print("Starting to poll for authentication status with state: \(pendingAuthState ?? "nil")")
    
    // Add more debug output
        if pendingAuthState == nil {
            print("ERROR: pendingAuthState is nil - polling will not work")
        }
        
        // Store merchant ID if provided
        if let merchantId = merchantId {
            self.merchantId = merchantId
        }
        
        // Poll the server every 3 seconds to check authentication status
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self, let state = self.pendingAuthState else {
                timer.invalidate()
                return
            }
            
            print("Polling for authentication status with state: \(state)")
            
            // Use the state parameter to check authentication status
            let urlString = "\(SquareConfig.backendBaseURL)\(SquareConfig.statusEndpoint)?state=\(state)"
            guard let url = URL(string: urlString) else {
                self.authError = "Invalid status URL"
                self.isAuthenticating = false
                timer.invalidate()
                return
            }
            
            URLSession.shared.dataTask(with: url) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Network error polling status: \(error)")
                        return // continue polling
                    }
                    
                    guard let data = data else {
                        print("No data received when polling")
                        return // continue polling
                    }
                    
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let connected = json["connected"] as? Bool, connected,
                               let accessToken = json["access_token"] as? String,
                               let refreshToken = json["refresh_token"] as? String,
                               let merchantId = json["merchant_id"] as? String,
                               let expiresAt = json["expires_at"] as? String {
                               
                                // Authentication successful - store tokens
                                self.accessToken = accessToken
                                self.refreshToken = refreshToken
                                self.merchantId = merchantId
                                
                                // Parse expiration date
                                let dateFormatter = ISO8601DateFormatter()
                                if let expirationDate = dateFormatter.date(from: expiresAt) {
                                    self.tokenExpirationDate = expirationDate
                                } else {
                                    self.tokenExpirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)
                                }
                                
                                self.pendingAuthState = nil
                                self.isAuthenticated = true
                                self.isAuthenticating = false
                                
                                print("Authentication successful! Tokens stored.")
                                timer.invalidate()
                            } else if let message = json["message"] as? String {
                                // Still waiting for authorization
                                print("Polling status: \(message)")
                            }
                        }
                    } catch {
                        print("Error parsing polling response: \(error)")
                    }
                }
            }.resume()
        }
        
        // Set a timeout after 2 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            timer.invalidate()
            
            guard let self = self, self.isAuthenticating else { return }
            
            self.authError = "Authentication timed out"
            self.isAuthenticating = false
            self.pendingAuthState = nil
            print("Authentication timed out after 2 minutes")
        }
        
        RunLoop.current.add(timer, forMode: .common)
    }
    
    // Replace the refreshAccessToken method
    func refreshAccessToken() {
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)\(SquareConfig.refreshEndpoint)") else {
            authError = "Invalid refresh URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "organization_id": SquareConfig.organizationId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            authError = "Failed to serialize request: \(error.localizedDescription)"
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.authError = "Network error: \(error.localizedDescription)"
                    self.isAuthenticated = false
                    return
                }
                
                guard let data = data else {
                    self.authError = "No data received"
                    self.isAuthenticated = false
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? String {
                            self.authError = "Refresh error: \(error)"
                            self.isAuthenticated = false
                            return
                        }
                        
                        if let success = json["success"] as? Bool, success {
                            self.isAuthenticated = true
                            print("Square token refreshed successfully!")
                        } else {
                            self.isAuthenticated = false
                        }
                    } else {
                        self.authError = "Invalid response format"
                        self.isAuthenticated = false
                    }
                } catch {
                    self.authError = "Failed to parse response: \(error.localizedDescription)"
                    self.isAuthenticated = false
                }
            }
        }.resume()
    }
    
    // Add a method to refresh the token automatically
    func refreshTokenIfNeeded() {
        // Check if we have a refresh token and if the token is expired or about to expire
        guard let refreshToken = refreshToken,
              let expirationDate = tokenExpirationDate else {
            return
        }
        
        // Refresh if token expires in less than 7 days (as recommended by Square)
        let sevenDaysInSeconds: TimeInterval = 7 * 24 * 60 * 60
        if Date().addingTimeInterval(sevenDaysInSeconds) > expirationDate {
            print("Access token will expire soon, refreshing...")
            refreshAccessToken(refreshToken: refreshToken)
        }
    }
    
    // Add a method to handle the callback from the backend
    func handleCallbackFromBackend(success: Bool) {
        isAuthenticating = false
        
        if success {
            isAuthenticated = true
            print("Successfully authenticated with Square via backend")
        } else {
            authError = "Authentication failed"
            isAuthenticated = false
        }
    }

    // Helper method to open the auth URL
    private func openAuthURL(_ url: URL) {
        // Don't do anything here - we're now handling opening the URL in SquareAuthorizationView
        print("Auth URL generated: \(url)")
        // The actual browser will be shown by the sheet in SquareAuthorizationView
    }
    
    // Helper method to refresh token with a refresh token
    private func refreshAccessToken(refreshToken: String) {
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)\(SquareConfig.refreshEndpoint)") else {
            authError = "Invalid refresh URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "refresh_token": refreshToken,
            "organization_id": SquareConfig.organizationId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            authError = "Failed to serialize request: \(error.localizedDescription)"
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.authError = "Network error: \(error.localizedDescription)"
                    self.isAuthenticated = false
                    return
                }
                
                guard let data = data else {
                    self.authError = "No data received"
                    self.isAuthenticated = false
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? String {
                            self.authError = "Refresh error: \(error)"
                            self.isAuthenticated = false
                            return
                        }
                        
                        if let success = json["success"] as? Bool, success,
                           let newAccessToken = json["access_token"] as? String,
                           let newRefreshToken = json["refresh_token"] as? String,
                           let newExpiresIn = json["expires_in"] as? Int {
                            
                            // Store new tokens
                            self.accessToken = newAccessToken
                            self.refreshToken = newRefreshToken
                            self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(newExpiresIn))
                            
                            self.isAuthenticated = true
                            print("Square token refreshed successfully!")
                        } else {
                            self.isAuthenticated = false
                        }
                    } else {
                        self.authError = "Invalid response format"
                        self.isAuthenticated = false
                    }
                } catch {
                    self.authError = "Failed to parse response: \(error.localizedDescription)"
                    self.isAuthenticated = false
                }
            }
        }.resume()
    }
}
