import SwiftUI

struct TimeoutSettingsView: View {
    @EnvironmentObject private var kioskStore: KioskStore
    @State private var timeoutDuration: String = "60"
    @State private var isSaving = false
    @State private var showToast = false
    
    let timeoutOptions = [
        ("15", "15 seconds"),
        ("30", "30 seconds"),
        ("60", "1 minute"),
        ("120", "2 minutes"),
        ("300", "5 minutes")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Timeout Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Configure how long the kiosk waits before resetting to the home screen.")
                        .foregroundColor(.gray)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        // Timeout options
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(timeoutOptions, id: \.0) { option in
                                RadioButton(
                                    id: option.0,
                                    label: option.1,
                                    isSelected: timeoutDuration == option.0,
                                    action: {
                                        timeoutDuration = option.0
                                    }
                                )
                            }
                        }
                        
                        // Info box
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Text("How timeout works")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                
                                Text("If no interaction is detected for the selected duration, the kiosk will automatically return to the home screen. This helps ensure the kiosk is ready for the next donor.")
                                    .foregroundColor(.orange.opacity(0.8))
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        
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
                                        Text("Save Settings")
                                    }
                                }
                                .padding()
                                .background(Color.indigo)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.85))
                    .cornerRadius(15)
                }
            }
            .padding()
            .frame(maxWidth: 600)
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
                timeoutDuration = kioskStore.timeoutDuration
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
            .navigationTitle("Timeout Settings")
        }
    }
    
    func saveSettings() {
        isSaving = true
        
        // Update the store
        kioskStore.timeoutDuration = timeoutDuration
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            kioskStore.saveSettings()
            isSaving = false
            showToast = true
        }
    }
}

struct RadioButton: View {
    let id: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.gray, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }
                
                Text(label)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding()
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TimeoutSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        TimeoutSettingsView()
            .environmentObject(KioskStore())
    }
}
