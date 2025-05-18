import SwiftUI

struct EmailReceiptsView: View {
    @EnvironmentObject private var organizationStore: OrganizationStore
    @State private var organizationName: String = ""
    @State private var taxId: String = ""
    @State private var isSaving = false
    @State private var showToast = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Email Receipts")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        // Organization Name
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Organization Name")
                                .font(.headline)
                            
                            TextField("Your Organization Name", text: $organizationName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        // Tax ID
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Tax ID (EIN)")
                                .font(.headline)
                            
                            TextField("12-3456789", text: $taxId)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Text("This will appear on donation receipts for tax purposes.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        // Save button
                        HStack {
                            Spacer()
                            
                            Button(action: saveSettings) {
                                HStack {
                                    if isSaving {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .padding(.trailing, 5)
                                        Text("Saving...")
                                    } else {
                                        Image(systemName: "square.and.arrow.down")
                                            .padding(.trailing, 5)
                                        Text("Save Changes")
                                    }
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.85))
                    .cornerRadius(15)
                }
            }
            .padding(.vertical)
            .padding(.horizontal, 24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .background(
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
            )
            .onAppear {
                organizationName = organizationStore.name
                taxId = organizationStore.taxId
            }
            .overlay(
                Group {
                    if showToast {
                        ToastView(message: "Settings saved successfully")
                            .transition(.move(edge: .top))
                            .animation(.spring(), value: showToast)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showToast = false
                                }
                            }
                    }
                }
            )
            .navigationTitle("Email Receipts")
        }
    }
    
    func saveSettings() {
        isSaving = true
        
        // Update the store
        organizationStore.name = organizationName
        organizationStore.taxId = taxId
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            organizationStore.saveToUserDefaults()
            isSaving = false
            showToast = true
        }
    }
}

struct EmailReceiptsView_Previews: PreviewProvider {
    static var previews: some View {
        EmailReceiptsView()
            .environmentObject(OrganizationStore())
    }
}
