import SwiftUI
import PhotosUI

struct HomePageSettingsView: View {
    @EnvironmentObject private var kioskStore: KioskStore
    @State private var headline: String = ""
    @State private var subtext: String = ""
    @State private var homePageEnabled = true
    @State private var showingLogoImagePicker = false
    @State private var showingBackgroundImagePicker = false
    @State private var isDirty = false
    @State private var isSaving = false
    @State private var showToast = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Enable/disable toggle
                HStack {
                    Spacer()
                    
                    Toggle("Home page is enabled", isOn: $homePageEnabled)
                        .padding()
                        .background(Color.white.opacity(0.85))
                        .cornerRadius(15)
                        .onChange(of: homePageEnabled) { _, _ in
                            isDirty = true
                        }
                }
                
                // Two column layout for iPad
                HStack(alignment: .top, spacing: 20) {
                    // Left column - Background Image
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Background Image")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Upload a background image for your donation kiosk home page.")
                            .foregroundColor(.gray)
                        
                        // Logo upload
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Organization Logo")
                                .font(.headline)
                            
                            HStack {
                                // Logo preview
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(8)
                                    
                                    if let logoImage = kioskStore.logoImage {
                                        Image(uiImage: logoImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 90, height: 90)
                                    } else {
                                        Image(systemName: "arrow.up.square")
                                            .font(.system(size: 30))
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                VStack(alignment: .leading) {
                                    Button("Upload Logo") {
                                        showingLogoImagePicker = true
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    if kioskStore.logoImage != nil {
                                        Button("Remove") {
                                            kioskStore.logoImage = nil
                                            isDirty = true
                                            // Save immediately to ensure persistence
                                            kioskStore.saveSettings()
                                        }
                                        .foregroundColor(.red)
                                    }
                                    
                                    Text("Recommended size: 200x200px")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.85))
                        .cornerRadius(15)
                        
                        // Background image upload
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Background Image")
                                .font(.headline)
                            
                            if let backgroundImage = kioskStore.backgroundImage {
                                ZStack {
                                    Image(uiImage: backgroundImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 200)
                                        .clipped()
                                        .cornerRadius(8)
                                    
                                    // Overlay with text preview
                                    VStack {
                                        Text(headline)
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        
                                        Text(subtext)
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(8)
                                }
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 200)
                                        .cornerRadius(8)
                                    
                                    VStack {
                                        Image(systemName: "arrow.up.square")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        
                                        Text("Upload a background image")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            
                            HStack {
                                Button("Upload Background") {
                                    showingBackgroundImagePicker = true
                                }
                                .buttonStyle(.bordered)
                                
                                if kioskStore.backgroundImage != nil {
                                    Button("Remove") {
                                        kioskStore.backgroundImage = nil
                                        isDirty = true
                                    }
                                    .foregroundColor(.red)
                                }
                            }
                            
                            Text("Recommended size: 1920x1080px. A dark overlay will be applied automatically.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.white.opacity(0.85))
                        .cornerRadius(15)
                    }
                    
                    // Right column - Text Content
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Text Content")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Set the headline and subtext that appears on your donation kiosk home page.")
                            .foregroundColor(.gray)
                        
                        VStack(alignment: .leading, spacing: 20) {
                            // Headline
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Headline")
                                    .font(.headline)
                                
                                TextField("Tap to Donate", text: $headline)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: headline) { _, _ in
                                        isDirty = true
                                    }
                                
                                Text("This is the main text displayed on the home screen.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            // Subtext
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Subtext")
                                    .font(.headline)
                                
                                TextEditor(text: $subtext)
                                    .frame(height: 100)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                                    .onChange(of: subtext) { _, _ in
                                        isDirty = true
                                    }
                                
                                Text("Additional text displayed below the headline.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            // Preview
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Preview")
                                    .font(.headline)
                                
                                VStack {
                                    Text(headline)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    Text(subtext)
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
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
                                    .background(isDirty ? Color.blue : Color.gray)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(!isDirty || isSaving)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.85))
                        .cornerRadius(15)
                    }
                }
            }
            .padding()
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
                headline = kioskStore.headline
                subtext = kioskStore.subtext
                homePageEnabled = kioskStore.homePageEnabled
            }
            .sheet(isPresented: $showingLogoImagePicker) {
                ImagePicker(selectedImage: $kioskStore.logoImage, isPresented: $showingLogoImagePicker)
                    .onDisappear {
                        if kioskStore.logoImage != nil {
                            isDirty = true
                        }
                    }
            }
            .sheet(isPresented: $showingBackgroundImagePicker) {
                ImagePicker(selectedImage: $kioskStore.backgroundImage, isPresented: $showingBackgroundImagePicker)
                    .onDisappear {
                        if kioskStore.backgroundImage != nil {
                            isDirty = true
                        }
                    }
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
            .navigationTitle("Home Page")
        }
    }
    
    func saveSettings() {
        isSaving = true
        
        // Update the store
        kioskStore.headline = headline
        kioskStore.subtext = subtext
        kioskStore.homePageEnabled = homePageEnabled
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            kioskStore.saveSettings()
            isSaving = false
            isDirty = false
            showToast = true
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.parent.selectedImage = image
                    }
                }
            }
        }
    }
}

struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .padding()
            .background(Color.black.opacity(0.7))
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.top, 20)
    }
}

struct HomePageSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        HomePageSettingsView()
            .environmentObject(KioskStore())
    }
}
