//
//  ContentView.swift
//  SimpleCamera
//
//  Created by Darragh Flynn on 20/03/2025.
//

//
//  ContentView.swift
//  SimpleCameraApp
//

import SwiftUI
import AVFoundation

// MARK: - Content View
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isCameraActive = false
    @State private var showPermissionAlert = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                // Camera preview (only shown when active)
                if isCameraActive {
                    CameraPreviewView(session: cameraManager.session)
                        .cornerRadius(12)
                        .padding()
                        .transition(.opacity)
                } else {
                    // Placeholder when camera is off
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .cornerRadius(12)
                        .padding()
                        .overlay(
                            Text("Camera Off")
                                .foregroundColor(.white)
                                .font(.title)
                        )
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Control buttons
                HStack(spacing: 40) {
                    Button(action: startCamera) {
                        Text("Start Camera")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 150)
                            .background(Color.green)
                            .cornerRadius(10)
                            .opacity(isCameraActive ? 0.5 : 1.0)
                    }
                    .disabled(isCameraActive)
                    
                    Button(action: stopCamera) {
                        Text("Stop Camera")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 150)
                            .background(Color.red)
                            .cornerRadius(10)
                            .opacity(isCameraActive ? 1.0 : 0.5)
                    }
                    .disabled(!isCameraActive)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            setupCamera()
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(
                title: Text("Camera Permission Required"),
                message: Text("This app needs camera access to function. Please enable it in Settings."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func setupCamera() {
        cameraManager.requestPermission { granted in
            if granted {
                cameraManager.setup()
            } else {
                showPermissionAlert = true
            }
        }
    }
    
    private func startCamera() {
        withAnimation {
            cameraManager.startCapture()
            isCameraActive = true
        }
    }
    
    private func stopCamera() {
        withAnimation {
            cameraManager.stopCapture()
            isCameraActive = false
        }
    }
}

// MARK: - Camera Manager
class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
    
    func setup() {
        // Run this on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Changed from .front to .back to use the back camera
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                return
            }
            
            self.session.beginConfiguration()
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            self.session.commitConfiguration()
        }
    }
    
    func startCapture() {
        // Run this on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func stopCapture() {
        // Run this on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
}

// MARK: - Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// MARK: - Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
// Don't forget to add this to Info.plist:
// <key>NSCameraUsageDescription</key>
// <string>This app needs camera access to show camera preview</string>

#Preview {
    ContentView()
}
