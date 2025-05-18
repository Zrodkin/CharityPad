import SwiftUI

struct OnboardingView: View {
    @State private var isLoading = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @EnvironmentObject private var organizationStore: OrganizationStore
    
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
                
                // Connect button
                Button(action: {
                    isLoading = true
                    
                    // Simulate connection delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        hasCompletedOnboarding = true
                        isLoading = false
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
    }
}

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

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(OrganizationStore())
    }
}
