import Foundation

struct SquareConfig {
  // Square application credentials
  static let clientID = "sq0idp-kt-6g2MHFsJB4J8uT5P-Fw"
  static let clientSecret = "sq0csp-wAgHmDXhxsayglxOuFSmAJ3ZnhZDVF2EKQd--WZ0pMc" // Updated with actual secret
  
  // Your backend server URL (without /api suffix)
  static let backendBaseURL = "https://charity-pad-server.vercel.app"
  
  // OAuth endpoints on your backend
  static let authorizeEndpoint = "/api/square/authorize"
  static let statusEndpoint = "/api/square/status"
  static let refreshEndpoint = "/api/square/refresh"
  static let disconnectEndpoint = "/api/square/disconnect"
  
  // Organization identifier
  static let organizationId = "default"
  
  // Production environment
  static let environment = "production"
  static let authorizeURL = "https://connect.squareup.com/oauth2/authorize"
  static let tokenURL = "https://connect.squareup.com/oauth2/token"
  static let revokeURL = "https://connect.squareup.com/oauth2/revoke"

  // Your app's redirect URI (must match what's configured in Square Developer Dashboard)
  static let redirectURI = "https://charity-pad-server.vercel.app/api/square/callback"
  
  // OAuth scopes needed for complete donation system functionality
  static let scopes = [
      "MERCHANT_PROFILE_READ",    // ✅ Already have - for merchant info and locations
      "PAYMENTS_WRITE",           // ✅ Already have - for processing payments
      "PAYMENTS_WRITE_IN_PERSON", // ✅ Already have - for in-person payments with Square hardware
      "PAYMENTS_READ",            // ✅ Already have - for reading payment details
      "ITEMS_READ",               // ❌ MISSING - Required for fetching preset donation amounts
      "ITEMS_WRITE",              // ❌ MISSING - Required for managing preset donation catalog
      "ORDERS_WRITE"              // ❌ MISSING - Required for creating donation orders
  ]
  
  // Generate the OAuth URL for authorization - using backend approach
  static func generateOAuthURL(completion: @escaping (URL?, Error?, String?) -> Void) {
      guard let url = URL(string: "\(backendBaseURL)\(authorizeEndpoint)?organization_id=\(organizationId)") else {
          completion(nil, NSError(domain: "com.charitypad", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"]), nil)
          return
      }
      
      print("Requesting OAuth URL from: \(url)")
      
      URLSession.shared.dataTask(with: url) { data, response, error in
          if let error = error {
              print("Network error requesting OAuth URL: \(error.localizedDescription)")
              completion(nil, error, nil)
              return
          }
          
          if let httpResponse = response as? HTTPURLResponse {
              print("Backend status code: \(httpResponse.statusCode)")
          }
          
          guard let data = data else {
              print("No data received from backend")
              completion(nil, NSError(domain: "com.charitypad", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data received"]), nil)
              return
          }
          
          // Print raw response for debugging
          let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
          print("Backend response: \(responseString)")
          
          do {
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
              if let authUrlString = json?["authUrl"] as? String, let authUrl = URL(string: authUrlString) {
                  // Store the state for CSRF protection
                  if let state = json?["state"] as? String {
                      // Use the key that matches what is used in SquareAuthService
                      UserDefaults.standard.set(state, forKey: "squarePendingAuthState")
                      print("Stored OAuth state: \(state)")
                      // Return the state to the caller
                      completion(authUrl, nil, state)
                      return
                  }
                  print("Generated OAuth URL: \(authUrl)")
                  completion(authUrl, nil, nil)
              } else if let error = json?["error"] as? String {
                  print("Backend error: \(error)")
                  completion(nil, NSError(domain: "com.charitypad", code: 3, userInfo: [NSLocalizedDescriptionKey: error]), nil)
              } else {
                  print("Invalid response format")
                  completion(nil, NSError(domain: "com.charitypad", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]), nil)
              }
          } catch {
              print("JSON parsing error: \(error.localizedDescription)")
              completion(nil, error, nil)
          }
      }.resume()
  }
}
