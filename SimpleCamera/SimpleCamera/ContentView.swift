//
//  ContentView.swift
//  MediaPipePoseApp
//

import SwiftUI
import AVFoundation
import MediaPipeTasksVision

// MARK: - Content View
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var poseDetector = PoseDetector()
    @State private var isCameraActive = false
    @State private var showPermissionAlert = false
    @State private var showPoseOverlay = true
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                // Camera preview with pose overlay
                if isCameraActive {
                    ZStack {
                        CameraPreviewView(session: cameraManager.session)
                        
                        if showPoseOverlay {
                            PoseOverlayView(posePoints: poseDetector.posePoints, connections: poseDetector.connections)
                        }
                    }
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
                HStack(spacing: 20) {
                    Button(action: startCamera) {
                        Text("Start Camera")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 120)
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
                            .frame(width: 120)
                            .background(Color.red)
                            .cornerRadius(10)
                            .opacity(isCameraActive ? 1.0 : 0.5)
                    }
                    .disabled(!isCameraActive)
                    
                    Button(action: toggleOverlay) {
                        Text(showPoseOverlay ? "Hide Pose" : "Show Pose")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 120)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
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
                cameraManager.onFrameCaptured = { sampleBuffer in
                    // Process frame with MediaPipe
                    self.poseDetector.processSampleBuffer(sampleBuffer)
                }
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
    
    private func toggleOverlay() {
        withAnimation {
            showPoseOverlay.toggle()
        }
    }
}

// MARK: - Camera Manager
class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.mediapipeapp.videoQueue")
    
    var onFrameCaptured: ((CMSampleBuffer) -> Void)?
    
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                return
            }
            
            self.session.beginConfiguration()
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            // Set optimal capture settings
            if let connection = self.videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = false
            }
            
            self.session.commitConfiguration()
        }
    }
    
    func startCapture() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    func stopCapture() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

// MARK: - Camera Delegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrameCaptured?(sampleBuffer)
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

// MARK: - Pose Detector
class PoseDetector: ObservableObject {
    private var poseLandmarker: PoseLandmarker?

    // Published properties for pose data
    @Published var posePoints: [CGPoint] =
    @Published var connections: [(Int, Int)] =
    private var videoSize: CGSize?

    init() {
        setupPoseDetector()
        setupConnectionList()
    }

    private func setupPoseDetector() {
        let modelPath = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task", inDirectory: "Models")

        guard let path = modelPath else {
            print("Error: Pose landmarker model not found in Models folder.")
            return
        }

        let options = PoseLandmarkerOptions()
        options.runningMode = .liveStream
        options.delegate = self
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5

        do {
            poseLandmarker = try PoseLandmarker.create(options: options, modelPath: path)
        } catch {
            print("Error creating pose landmarker: \(error)")
        }
    }

    private func setupConnectionList() {
        // Define the connections between pose landmarks (using MediaPipe's standard indices)
        connections = [
            (0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8), (9, 10),
            (11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (15, 17), (17, 19),
            (19, 15), (15, 21), (17, 21), (12, 16), (16, 18), (18, 20), (20, 16),
            (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (27, 29), (29, 31),
            (24, 26), (26, 28), (28, 30), (30, 32)
        ]
    }

    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let poseLandmarker = poseLandmarker,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let currentTimeMs = Date().timeIntervalSince1970 * 1000

        do {
            let mpImage = MLImage(pixelBuffer: pixelBuffer)
            if videoSize == nil {
                videoSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            }
            try poseLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: Int(currentTimeMs))
        } catch {
            print("Error running pose landmarker: \(error)")
        }
    }

    private func updatePosePoints(from result: PoseLandmarkerResult?) {
        guard let result = result, let landmarks = result.poseLandmarks.first else {
            self.posePoints =
            return
        }

        guard let videoSize = self.videoSize else { return }

        // Convert normalized landmarks to points based on video size
        self.posePoints = landmarks.landmark.map { landmark in
            CGPoint(x: CGFloat(landmark.x) * videoSize.width, y: CGFloat(landmark.y) * videoSize.height)
        }
    }
}

// MARK: - PoseLandmarkerDelegate
extension PoseDetector: PoseLandmarkerDelegate {
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: Result<PoseLandmarkerResult, Error>) {
        switch result {
        case .success(let poseResult):
            DispatchQueue.main.async {
                self.updatePosePoints(from: poseResult)
            }
        case .failure(let error):
            print("Pose estimation failed: \(error)")
        }
    }
}
// MARK: - Pose Overlay View
struct PoseOverlayView: View {
    let posePoints: [CGPoint]
    let connections: [(Int, Int)]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Draw connections
                ForEach(0..<connections.count, id: \.self) { index in
                    if connections[index].0 < posePoints.count && connections[index].1 < posePoints.count {
                        let start = posePoints[connections[index].0]
                        let end = posePoints[connections[index].1]
                        
                        Path { path in
                            path.move(to: CGPoint(
                                x: start.x * geometry.size.width,
                                y: start.y * geometry.size.height
                            ))
                            path.addLine(to: CGPoint(
                                x: end.x * geometry.size.width,
                                y: end.y * geometry.size.height
                            ))
                        }
                        .stroke(Color.red, lineWidth: 2)
                    }
                }
                
                // Draw landmarks
                ForEach(0..<posePoints.count, id: \.self) { index in
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .position(
                            x: posePoints[index].x * geometry.size.width,
                            y: posePoints[index].y * geometry.size.height
                        )
                }
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

////
////  ContentView.swift
////  SimpleCamera
////
////  Created by Darragh Flynn on 20/03/2025.
////
//
////
////  ContentView.swift
////  SimpleCameraApp
////
//
//import SwiftUI
//import AVFoundation
//
//// MARK: - Content View
//struct ContentView: View {
//    @StateObject private var cameraManager = CameraManager()
//    @State private var isCameraActive = false
//    @State private var showPermissionAlert = false
//    
//    var body: some View {
//        ZStack {
//            Color.black.edgesIgnoringSafeArea(.all)
//            
//            VStack {
//                // Camera preview (only shown when active)
//                if isCameraActive {
//                    CameraPreviewView(session: cameraManager.session)
//                        .cornerRadius(12)
//                        .padding()
//                        .transition(.opacity)
//                } else {
//                    // Placeholder when camera is off
//                    Rectangle()
//                        .fill(Color.gray.opacity(0.3))
//                        .cornerRadius(12)
//                        .padding()
//                        .overlay(
//                            Text("Camera Off")
//                                .foregroundColor(.white)
//                                .font(.title)
//                        )
//                        .transition(.opacity)
//                }
//                
//                Spacer()
//                
//                // Control buttons
//                HStack(spacing: 40) {
//                    Button(action: startCamera) {
//                        Text("Start Camera")
//                            .font(.headline)
//                            .foregroundColor(.white)
//                            .padding()
//                            .frame(width: 150)
//                            .background(Color.green)
//                            .cornerRadius(10)
//                            .opacity(isCameraActive ? 0.5 : 1.0)
//                    }
//                    .disabled(isCameraActive)
//                    
//                    Button(action: stopCamera) {
//                        Text("Stop Camera")
//                            .font(.headline)
//                            .foregroundColor(.white)
//                            .padding()
//                            .frame(width: 150)
//                            .background(Color.red)
//                            .cornerRadius(10)
//                            .opacity(isCameraActive ? 1.0 : 0.5)
//                    }
//                    .disabled(!isCameraActive)
//                }
//                .padding(.bottom, 30)
//            }
//        }
//        .onAppear {
//            setupCamera()
//        }
//        .alert(isPresented: $showPermissionAlert) {
//            Alert(
//                title: Text("Camera Permission Required"),
//                message: Text("This app needs camera access to function. Please enable it in Settings."),
//                dismissButton: .default(Text("OK"))
//            )
//        }
//    }
//    
//    private func setupCamera() {
//        cameraManager.requestPermission { granted in
//            if granted {
//                cameraManager.setup()
//            } else {
//                showPermissionAlert = true
//            }
//        }
//    }
//    
//    private func startCamera() {
//        withAnimation {
//            cameraManager.startCapture()
//            isCameraActive = true
//        }
//    }
//    
//    private func stopCamera() {
//        withAnimation {
//            cameraManager.stopCapture()
//            isCameraActive = false
//        }
//    }
//}
//
//// MARK: - Camera Manager
//class CameraManager: NSObject, ObservableObject {
//    let session = AVCaptureSession()
//    private var videoOutput = AVCaptureVideoDataOutput()
//    
//    func requestPermission(completion: @escaping (Bool) -> Void) {
//        switch AVCaptureDevice.authorizationStatus(for: .video) {
//        case .authorized:
//            completion(true)
//        case .notDetermined:
//            AVCaptureDevice.requestAccess(for: .video) { granted in
//                DispatchQueue.main.async {
//                    completion(granted)
//                }
//            }
//        default:
//            completion(false)
//        }
//    }
//    
//    func setup() {
//        // Run this on a background thread
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            guard let self = self else { return }
//            
//            // Changed from .front to .back to use the back camera
//            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
//                  let input = try? AVCaptureDeviceInput(device: camera) else {
//                return
//            }
//            
//            self.session.beginConfiguration()
//            
//            if self.session.canAddInput(input) {
//                self.session.addInput(input)
//            }
//            
//            if self.session.canAddOutput(self.videoOutput) {
//                self.session.addOutput(self.videoOutput)
//            }
//            
//            self.session.commitConfiguration()
//        }
//    }
//    
//    func startCapture() {
//        // Run this on a background thread
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            guard let self = self else { return }
//            if !self.session.isRunning {
//                self.session.startRunning()
//            }
//        }
//    }
//    
//    func stopCapture() {
//        // Run this on a background thread
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            guard let self = self else { return }
//            if self.session.isRunning {
//                self.session.stopRunning()
//            }
//        }
//    }
//}
//
//// MARK: - Camera Preview View
//struct CameraPreviewView: UIViewRepresentable {
//    let session: AVCaptureSession
//    
//    func makeUIView(context: Context) -> UIView {
//        let view = UIView(frame: .zero)
//        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
//        previewLayer.videoGravity = .resizeAspectFill
//        view.layer.addSublayer(previewLayer)
//        return view
//    }
//    
//    func updateUIView(_ uiView: UIView, context: Context) {
//        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
//            DispatchQueue.main.async {
//                previewLayer.frame = uiView.bounds
//            }
//        }
//    }
//}
//
//// MARK: - Preview Provider
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
//// Don't forget to add this to Info.plist:
//// <key>NSCameraUsageDescription</key>
//// <string>This app needs camera access to show camera preview</string>
//
//#Preview {
//    ContentView()
//}
