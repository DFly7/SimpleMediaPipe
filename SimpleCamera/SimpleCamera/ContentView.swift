import SwiftUI
import AVFoundation
import MediaPipeTasksVision
import UIKit
import Starscream

// MARK: - Main App View
struct ContentView: View {
    @State private var isShowingHomeScreen = true
    
    var body: some View {
        if isShowingHomeScreen {
            HomeScreenView(onStartSwinging: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isShowingHomeScreen = false
                }
            })
        } else {
            SwingAnalysisView(onBackPressed: {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isShowingHomeScreen = true
                }
            })
        }
    }
}

// MARK: - Home Screen View
struct HomeScreenView: View {
    var onStartSwinging: () -> Void
    @State private var isButtonAnimating = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color(#colorLiteral(red: 0.1019607857, green: 0.2784313858, blue: 0.400000006, alpha: 1)), Color(#colorLiteral(red: 0.09019608051, green: 0.1921568662, blue: 0.2549019754, alpha: 1))]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            // Animated background elements (golf ball effect)
            ForEach(0..<20) { index in
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: CGFloat.random(in: 20...100))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
            }
            
            VStack(spacing: 30) {
                Spacer()
                
                // App title
                VStack(spacing: 12) {
                    Text("SWING")
                        .font(.system(size: 60, weight: .heavy))
                        .foregroundColor(.white)
                    
                    Text("ANALYSER")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(Color(#colorLiteral(red: 0.4666666687, green: 0.7647058964, blue: 0.2666666806, alpha: 1)))
                }
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Spacer()
                
                // Subtitle
                Text("Improve your swing with\nreal-time pose analysis")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 20)
                
                Spacer()
                
                // Start button
                Button(action: onStartSwinging) {
                    Text("START SWINGING")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 40)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color(#colorLiteral(red: 0.4666666687, green: 0.7647058964, blue: 0.2666666806, alpha: 1)))
                                .shadow(color: Color(#colorLiteral(red: 0.4666666687, green: 0.7647058964, blue: 0.2666666806, alpha: 1)).opacity(0.5), radius: 8, x: 0, y: 4)
                        )
                        .scaleEffect(isButtonAnimating ? 1.05 : 1.0)
                }
                .onAppear {
                    // Subtle button animation to draw attention
                    withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isButtonAnimating = true
                    }
                }
                
                Spacer()
                
                // Footer text
                Text("Powered by MediaPipe & AI")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 20)
            }
            .padding()
        }
    }
}

// MARK: - Swing Analysis View (the original camera view)
struct SwingAnalysisView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var socketManager = WebSocketManager()
    @State private var isCameraActive = false
    @State private var showPermissionAlert = false
    @State private var lastScore: Int = 0
    @State private var showControls = true
    @State private var showBottomPanel = true
    @State private var showPoseOverlay = true
    var onBackPressed: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Professional dark background
                Color(#colorLiteral(red: 0.05882352941, green: 0.09019607843, blue: 0.1098039216, alpha: 1)).edgesIgnoringSafeArea(.all)
                
                // Full-screen camera view, always fills the entire screen
                ZStack {
                    // Camera preview (only shown when active)
                    if isCameraActive {
                        CameraPreviewView(session: cameraManager.session)
                            .overlay(
                                // Pose overlay view (only show if enabled)
                                showPoseOverlay ? PoseOverlayView(poseResults: cameraManager.poseResults) : nil
                            )
                            .edgesIgnoringSafeArea(.all)
                    } else {
                        // Placeholder when camera is off
                        ZStack {
                            Color(#colorLiteral(red: 0.1298420429, green: 0.1298461258, blue: 0.1298439503, alpha: 1)).edgesIgnoringSafeArea(.all)
                            VStack(spacing: 20) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text("Camera Off")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    
                                Text("Tap 'Start Analysis' to begin")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    
                    // Overlay elements that stay on top of camera view
                    VStack {
                        // Semi-transparent top status bar
                        HStack {
                            // Back button
                            Button(action: onBackPressed) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Home")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                            }
                            
                            Spacer()
                            
                            // Toggle bottom panel button
                            Button(action: {
                                withAnimation(.spring()) {
                                    showBottomPanel.toggle()
                                }
                            }) {
                                Image(systemName: showBottomPanel ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            
                            Spacer()
                            
                            // Connection status with subtle background
                            if socketManager.isConnected {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("Connected")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(16)
                            } else {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("Not Connected")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(16)
                            }
                        }
                        .padding(12)
                        .padding(.top, geometry.safeAreaInsets.top)
                        
                        Spacer()
                        
                        // Only show the score display
                        if socketManager.lastScore > 0 {
                            VStack(spacing: 0) {
                                // Score header
                                Text("SWING SCORE")
                                    .font(.system(size: 12, weight: .heavy))
                                    .tracking(1.5)
                                    .foregroundColor(.white.opacity(0.9))
                                
                                // Score value
                                Text("\(socketManager.lastScore)")
                                    .font(.system(size: 48, weight: .heavy))
                                    .foregroundColor(scoreColor(for: socketManager.lastScore))
                                
                                // Score description
                                Text(scoreDescription(for: socketManager.lastScore))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 10)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.7))
                                    .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
                            )
                            .padding(.bottom, showBottomPanel ? 20 : (geometry.safeAreaInsets.bottom + 30))
                        }
                        
                        // Analyzing indicator when active (ONLY shown if camera is active)
                        if isCameraActive && !showBottomPanel {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                                    .opacity(sin(Date().timeIntervalSince1970 * 2) > 0 ? 1 : 0.3) // Blinking effect
                                
                                Text("ANALYSING")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(20)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 10)
                        }
                    }
                }
                
                // Bottom control panel (slides in/out)
                if showBottomPanel {
                    VStack {
                        Spacer()
                        
                        ZStack {
                            // Semi-transparent background
                            Color(#colorLiteral(red: 0.09803921569, green: 0.1294117647, blue: 0.1490196078, alpha: 1))
                                .edgesIgnoringSafeArea(.bottom)
                            
                            VStack(spacing: 20) {
                                // Tools and options
                                HStack(spacing: 25) {
                                    // Reconnect button
                                    VStack(spacing: 6) {
                                        Button(action: {
                                            socketManager.reconnect()
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.blue.opacity(0.2))
                                                    .frame(width: 48, height: 48)
                                                
                                                Image(systemName: "arrow.triangle.2.circlepath")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        Text("Reconnect")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    
                                    // Primary analysis control
                                    VStack(spacing: 10) {
                                        ZStack {
                                            // Outer ring
                                            Circle()
                                                .stroke(
                                                    isCameraActive ? Color.red : Color.green,
                                                    lineWidth: 4
                                                )
                                                .frame(width: 74, height: 74)
                                            
                                            // Inner button
                                            Button(action: isCameraActive ? stopCamera : startCamera) {
                                                Circle()
                                                    .fill(isCameraActive ? Color.red : Color.green)
                                                    .frame(width: 60, height: 60)
                                                    .overlay(
                                                        ZStack {
                                                            if isCameraActive {
                                                                RoundedRectangle(cornerRadius: 4)
                                                                    .fill(Color.white)
                                                                    .frame(width: 20, height: 20)
                                                            } else {
                                                                Circle()
                                                                    .stroke(Color.white, lineWidth: 2)
                                                                    .frame(width: 22, height: 22)
                                                            }
                                                        }
                                                    )
                                            }
                                        }
                                        Text(isCameraActive ? "Stop" : "Start Analysis")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                    
                                    Spacer()
                                    
                                    // Toggle controls visibility button
                                    VStack(spacing: 6) {
                                        Button(action: {
                                            withAnimation(.spring()) {
                                                showControls.toggle()
                                            }
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(white: 0.3, opacity: 0.2))
                                                    .frame(width: 48, height: 48)
                                                
                                                Image(systemName: "slider.horizontal.3")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        Text("Controls")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .padding(.horizontal, 30)
                                .padding(.top, 20)
                                
                                // Analysing indicator in bottom panel when active
                                if isCameraActive {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 12, height: 12)
                                            .opacity(sin(Date().timeIntervalSince1970 * 2) > 0 ? 1 : 0.3) // Blinking effect
                                        
                                        Text("ANALYSING")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 14)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(20)
                                }
                                
                                // Session info and messages
                                if showControls {
                                    VStack(spacing: 14) {
                                        Divider()
                                            .background(Color.white.opacity(0.2))
                                            .padding(.horizontal, 40)
                                        
                                        // Toggle for Pose Overlay
                                        Button(action: {
                                            withAnimation {
                                                showPoseOverlay.toggle()
                                            }
                                        }) {
                                            HStack {
                                                // Text and icon for the toggle
                                                HStack(spacing: 8) {
                                                    Image(systemName: "figure.stand")
                                                        .font(.system(size: 15))
                                                        .foregroundColor(.white)
                                                    
                                                    Text("Pose Overlay")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(.white)
                                                }
                                                
                                                Spacer()
                                                
                                                // Custom toggle indicator
                                                ZStack {
                                                    Capsule()
                                                        .fill(showPoseOverlay ? Color.green.opacity(0.5) : Color.gray.opacity(0.5))
                                                        .frame(width: 50, height: 26)
                                                    
                                                    Circle()
                                                        .fill(showPoseOverlay ? Color.green : Color.gray)
                                                        .frame(width: 22, height: 22)
                                                        .offset(x: showPoseOverlay ? 12 : -12)
                                                        .animation(.spring(), value: showPoseOverlay)
                                                }
                                            }
                                            .padding(.horizontal, 30)
                                            .padding(.vertical, 10)
                                            .background(Color.black.opacity(0.2))
                                            .cornerRadius(10)
                                            .padding(.horizontal, 20)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        Divider()
                                            .background(Color.white.opacity(0.2))
                                            .padding(.horizontal, 40)
                                            .padding(.vertical, 5)
                                        
                                        // Latest message from server
                                        if !socketManager.lastFeedback.isEmpty {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("SERVER MESSAGE")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white.opacity(0.5))
                                                
                                                Text(socketManager.lastFeedback)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.9))
                                                    .multilineTextAlignment(.leading)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .padding(.horizontal, 30)
                                        }
                                        
                                        HStack(spacing: 20) {
                                            // Socket status
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("SERVER STATUS")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white.opacity(0.5))
                                                
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(socketManager.isConnected ? Color.green : Color.red)
                                                        .frame(width: 8, height: 8)
                                                    
                                                    Text(socketManager.isConnected ? "Connected" : "Disconnected")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(.white.opacity(0.8))
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            // Session info
                                            VStack(alignment: .trailing, spacing: 6) {
                                                Text("IP ADDRESS")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white.opacity(0.5))
                                                
                                                Text("192.168.7.92:5001")
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                        }
                                        .padding(.horizontal, 30)
                                        .padding(.bottom, 20)
                                    }
                                }
                            }
                        }
                        .frame(height: geometry.size.height * 0.30)
                        .transition(.move(edge: .bottom))
                    }
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            setupCamera()
            // Set up the score observation
            setupScoreObserver()
        }
        .onDisappear {
            socketManager.disconnect()
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(
                title: Text("Camera Permission Required"),
                message: Text("This app needs camera access to function. Please enable it in Settings."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // Function to determine score color based on score value
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 0...30:
            return Color(#colorLiteral(red: 0.9254902005, green: 0.2352941185, blue: 0.1019607857, alpha: 1))
        case 31...70:
            return Color(#colorLiteral(red: 0.9529411793, green: 0.6862745285, blue: 0.1333333403, alpha: 1))
        default:
            return Color(#colorLiteral(red: 0.4666666687, green: 0.7647058964, blue: 0.2666666806, alpha: 1))
        }
    }
    
    // Function to get score description
    private func scoreDescription(for score: Int) -> String {
        switch score {
        case 0...30:
            return "Needs improvement"
        case 31...70:
            return "Good technique"
        default:
            return "Excellent form!"
        }
    }
    
    // Setup observer for score updates
    private func setupScoreObserver() {
        // Observe when score changes
        socketManager.onScoreReceived = { score in
            withAnimation(.spring()) {
                self.lastScore = score
            }
        }
    }
    
    private func setupCamera() {
        cameraManager.requestPermission { granted in
            if granted {
                cameraManager.setup()
                // Connect the socket manager to the camera manager
                cameraManager.setSocketManager(socketManager)
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
            // Notify the server that camera is being stopped
            socketManager.sendStopNotification()
            
            // Then stop the camera capture
            cameraManager.stopCapture()
            isCameraActive = false
        }
    }
}

// MARK: - Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#Preview {
    ContentView()
}

// Define a custom landmark structure to simplify working with landmarks
struct PoseLandmark: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let z: CGFloat
    let visibility: Float
}

// MARK: - Camera Manager
class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var poseDetector: PoseDetector?
    
    @Published var poseResults: [PoseLandmark] = []
    private var currentFrameTimestamp: Int64 = 0
    
    // Add reference to SocketManager
    private var socketManager: WebSocketManager?
    
    // Add properties to handle pose persistence between frames
    private var lastValidPoseTimestamp: TimeInterval = 0
    private let posePersistenceDuration: TimeInterval = 0.3 // Hold pose for 300ms before clearing
    
    func setSocketManager(_ manager: WebSocketManager) {
        self.socketManager = manager
    }
    
    override init() {
        super.init()
        initializePoseDetector()
    }
    
    private func initializePoseDetector() {
        poseDetector = PoseDetector(suppressWarnings: true)
        poseDetector?.initializeDetector()
    }
    
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
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                return
            }
            
            self.session.beginConfiguration()
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            
            // ADD THIS PART: Set the specific pixel format that MediaPipe requires
            let settings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.videoSettings = settings
            // END OF ADDED PART
            
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoProcessingQueue"))
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            // Set video orientation if needed
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                connection.isVideoMirrored = false
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
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Get frame timestamp
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).value
        
        currentFrameTimestamp = timestamp
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Process frame with pose detector
        if let (poseLandmarks, worldLandmarks) = poseDetector?.detectPoseInVideo(on: pixelBuffer, timestamp: timestamp) {
            DispatchQueue.main.async {
                // Use poseLandmarks for visualization if they exist
                if let validPoseLandmarks = poseLandmarks, !validPoseLandmarks.isEmpty {
                    self.poseResults = validPoseLandmarks
                    self.lastValidPoseTimestamp = Date().timeIntervalSince1970
                } else {
                    // Only clear pose data if enough time has passed since the last valid pose
                    let currentTime = Date().timeIntervalSince1970
                    if currentTime - self.lastValidPoseTimestamp > self.posePersistenceDuration {
                        self.poseResults = []
                    }
                    // Otherwise keep the last valid pose to prevent flickering
                }
                
                // Only send world landmarks if available
                if let validWorldLandmarks = worldLandmarks, !validWorldLandmarks.isEmpty {
                    self.socketManager?.sendWorldKeypoints(landmarks: validWorldLandmarks)
                }
            }
        } else {
            // Same debounce logic for nil detection results
            DispatchQueue.main.async {
                let currentTime = Date().timeIntervalSince1970
                if currentTime - self.lastValidPoseTimestamp > self.posePersistenceDuration {
                    self.poseResults = []
                }
            }
        }
    }
}

// MARK: - Pose Detector
class PoseDetector: NSObject, PoseLandmarkerLiveStreamDelegate {
    private var poseDetector: PoseLandmarker?
    private var lastTimestamp: Int64 = 0
    private var currentPoseResult: PoseLandmarkerResult?
    private var hasNewData = false
    
    // Better timestamp tracking with a larger increment
    private var lastProcessedTimestamp: Int = 0
    private let timestampIncrement = 100 // Use a larger increment to avoid small differences
    
    // Add debounce properties to smooth out detection
    private var lastValidResultTime: TimeInterval = 0
    private var cachedLandmarks: [PoseLandmark]?
    private var cachedWorldLandmarks: [PoseLandmark]?
    
    // Add this property to suppress MediaPipe output
    private var suppressWarnings: Bool = true
    
    init(suppressWarnings: Bool = true) {
        super.init()
        self.suppressWarnings = suppressWarnings
        
        // Suppress MediaPipe warnings by redirecting stderr if needed
        if suppressWarnings {
            redirectStderrToNull()
        }
    }
    
    deinit {
        // Restore stderr if we redirected it
        if suppressWarnings {
            restoreStderr()
        }
    }
    
    // Function to redirect stderr to /dev/null (suppresses warnings)
    private func redirectStderrToNull() {
        freopen("/dev/null", "w", stderr)
    }
    
    // Function to restore stderr
    private func restoreStderr() {
        fclose(stderr)
        freopen("/dev/stderr", "w", stderr)
    }
    
    func initializeDetector() {
        // Find the model file path
        var modelPath: String?
        
        // Try different approaches to find the model file
        modelPath = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task", inDirectory: "Models")
        
        if modelPath == nil {
            modelPath = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task")
            print("Model found at: \(modelPath ?? "nil")")
        }
        
        guard let finalModelPath = modelPath else {
            print("Failed to locate pose model file")
            return
        }
        
        do {
            // Set up options for video mode
            let poseOptions = PoseLandmarkerOptions()
            poseOptions.baseOptions.modelAssetPath = finalModelPath
            
            // For increased performance and to avoid timestamp warnings:
            poseOptions.runningMode = .liveStream
            poseOptions.numPoses = 1
            
            // Adjust MediaPipe detection options to minimize warnings
            // Set min detection confidence to avoid flickering and reduce warnings
            poseOptions.minPoseDetectionConfidence = 0.9
            poseOptions.minPosePresenceConfidence = 0.9
            poseOptions.minTrackingConfidence = 0.9
            
            // Set self as the delegate
            poseOptions.poseLandmarkerLiveStreamDelegate = self
            
            // Create the pose landmarker
            poseDetector = try PoseLandmarker(options: poseOptions)
            print("Successfully initialized pose detector")
        } catch {
            print("Failed to initialize pose detector: \(error)")
        }
    }
    
    // MARK: - PoseLandmarkerLiveStreamDelegate
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, 
                        didFinishDetection result: PoseLandmarkerResult?, 
                        timestampInMilliseconds timestamp: Int, 
                        error: Error?) {
        if let error = error {
            print("Pose detection error: \(error)")
            return
        }
        
        // Make sure to only update if we actually have a result with landmarks
        if let validResult = result, !validResult.landmarks.isEmpty {
            self.currentPoseResult = validResult
            self.hasNewData = true
            print("Got pose detection result with \(validResult.landmarks[0].count) landmarks")
            
            // Also print information about world landmarks if available
            if !validResult.worldLandmarks.isEmpty {
                print("Got pose world landmarks with \(validResult.worldLandmarks[0].count) points")
            }
        }
    }
    
    func detectPoseInVideo(on pixelBuffer: CVPixelBuffer, timestamp: Int64) -> (poseLandmarks: [PoseLandmark]?, worldLandmarks: [PoseLandmark]?) {
        guard let poseDetector = poseDetector else { return (nil, nil) }
        
        do {
            let mpImage = try MPImage(pixelBuffer: pixelBuffer)
            
            // Use a significantly larger timestamp increment to avoid small differences
            lastProcessedTimestamp += timestampIncrement
            
            // For live stream mode, pass the frame and strictly increasing timestamp
            try poseDetector.detectAsync(image: mpImage, timestampInMilliseconds: lastProcessedTimestamp)
            
            // Return the most recent result (might be from a previous frame)
            if hasNewData, let poseResult = currentPoseResult, !poseResult.landmarks.isEmpty {
                hasNewData = false // Reset flag until next new result
                
                var customLandmarks: [PoseLandmark] = []
                var customWorldLandmarks: [PoseLandmark] = []
                
                // Process normal landmarks
                for (index, landmark) in poseResult.landmarks[0].enumerated() {
                    let customLandmark = PoseLandmark(
                        id: index,
                        x: CGFloat(landmark.x),
                        y: CGFloat(landmark.y),
                        z: CGFloat(landmark.z),
                        visibility: Float(landmark.visibility ?? 1.0)
                    )
                    customLandmarks.append(customLandmark)
                }
                
                // Process world landmarks if available
                if !poseResult.worldLandmarks.isEmpty {
                    for (index, landmark) in poseResult.worldLandmarks[0].enumerated() {
                        let customWorldLandmark = PoseLandmark(
                            id: index,
                            x: CGFloat(landmark.x),
                            y: CGFloat(landmark.y),
                            z: CGFloat(landmark.z),
                            visibility: Float(landmark.visibility ?? 1.0)
                        )
                        customWorldLandmarks.append(customWorldLandmark)
                    }
                }
                
                // Cache the valid landmarks with timestamp
                self.cachedLandmarks = customLandmarks
                self.cachedWorldLandmarks = customWorldLandmarks
                self.lastValidResultTime = Date().timeIntervalSince1970
                
                return (customLandmarks, customWorldLandmarks)
            } else {
                // Return cached landmarks if we have them and they're recent
                let currentTime = Date().timeIntervalSince1970
                let cacheValidityDuration: TimeInterval = 0.5 // Landmarks valid for 500ms
                
                if let cached = self.cachedLandmarks, currentTime - self.lastValidResultTime < cacheValidityDuration {
                    return (cached, self.cachedWorldLandmarks)
                }
                
                // If cache expired or no cache, return empty results
                return ([], [])
            }
        } catch {
            print("Pose detection failed: \(error)")
        }
        
        return (nil, nil)
    }
}

// MARK: - Pose Overlay View
struct PoseOverlayView: View {
    var poseResults: [PoseLandmark]
    
    // Define different body part groups with different colors
    let connectionGroups: [(connections: [(fromIndex: Int, toIndex: Int)], color: Color)] = [
        // Face oval - light blue
        ([(0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8)], Color(red: 0.2, green: 0.8, blue: 1.0)),
        
        // Left arm - gold
        ([(11, 13), (13, 15), (15, 17), (15, 19), (15, 21), (17, 19)], Color(red: 0.9, green: 0.7, blue: 0.0)),
        
        // Right arm - green
        ([(12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20)], Color(red: 0.0, green: 0.8, blue: 0.2)),
        
        // Torso - purple
        ([(11, 12), (11, 23), (12, 24), (23, 24)], Color(red: 0.8, green: 0.2, blue: 0.8)),
        
        // Left leg - red
        ([(23, 25), (25, 27), (27, 29), (27, 31), (29, 31)], Color(red: 0.9, green: 0.2, blue: 0.2)),
        
        // Right leg - blue
        ([(24, 26), (26, 28), (28, 30), (28, 32), (30, 32)], Color(red: 0.2, green: 0.4, blue: 0.9))
    ]
    
    // Define different landmark types with specific styles
    func landmarkStyle(for index: Int) -> (color: Color, size: CGFloat) {
        // Face landmarks (smaller, orange)
        if index <= 10 {
            return (Color.orange, 6)
        }
        
        // Wrist landmarks (medium, bright red)
        else if index == 15 || index == 16 {
            return (Color.red.opacity(0.9), 8)
        }
        
        // Hip landmarks (larger, purple)
        else if index == 23 || index == 24 {
            return (Color.purple, 10)
        }
        
        // Other landmarks (medium, white)
        else {
            return (Color.white, 7)
        }
    }
    
    // Check if we have valid landmarks to draw - strict version with no delay
    private func hasValidPose() -> Bool {
        // Check if we have enough landmarks
        guard !poseResults.isEmpty && poseResults.count >= 33 else {
            return false
        }
        
        // Require BOTH shoulders to be visible with high confidence
        let leftShoulderVisible = poseResults[11].visibility > 0.7
        let rightShoulderVisible = poseResults[12].visibility > 0.7
        
        // Require at least both shoulders to be visible
        return (leftShoulderVisible && rightShoulderVisible)
    }
    
    // Create a custom connection struct to handle z-ordering
    private struct Connection: Identifiable, Comparable {
        let id = UUID()
        let fromIndex: Int
        let toIndex: Int
        let color: Color
        let zValue: CGFloat
        let groupIndex: Int
        
        // Implement Comparable to sort by z-value
        static func < (lhs: Connection, rhs: Connection) -> Bool {
            // Negative comparison because larger z values are further away
            return lhs.zValue > rhs.zValue
        }
        
        // Implement Equatable
        static func == (lhs: Connection, rhs: Connection) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    // Create a custom landmark struct to handle z-ordering
    private struct DrawableLandmark: Identifiable, Comparable {
        let id = UUID()
        let originalIndex: Int
        let position: CGPoint
        let style: (color: Color, size: CGFloat)
        let zValue: CGFloat
        
        // Implement Comparable to sort by z-value
        static func < (lhs: DrawableLandmark, rhs: DrawableLandmark) -> Bool {
            // Negative comparison because larger z values are further away
            return lhs.zValue > rhs.zValue
        }
        
        // Implement Equatable
        static func == (lhs: DrawableLandmark, rhs: DrawableLandmark) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if !poseResults.isEmpty && hasValidPose() {
                ZStack {
                    // Prepare all connections with z-order information
                    let sortedConnections = prepareConnectionsWithDepth(geometry: geometry)
                    
                    // Draw connections in z-order (from back to front)
                    ForEach(sortedConnections) { connection in
                        if connection.fromIndex < poseResults.count && connection.toIndex < poseResults.count {
                            let fromLandmark = poseResults[connection.fromIndex]
                            let toLandmark = poseResults[connection.toIndex]
                            
                            // Only draw connections if both landmarks have reasonable visibility
                            if fromLandmark.visibility > 0.2 && toLandmark.visibility > 0.2 {
                                // Calculate positions
                                let fromPoint = CGPoint(
                                    x: fromLandmark.x * geometry.size.width,
                                    y: fromLandmark.y * geometry.size.height
                                )
                                let toPoint = CGPoint(
                                    x: toLandmark.x * geometry.size.width,
                                    y: toLandmark.y * geometry.size.height
                                )
                                
                                // Draw connection with proper styling and anti-aliasing
                                Path { path in
                                    path.move(to: fromPoint)
                                    path.addLine(to: toPoint)
                                }
                                .stroke(connection.color, style: StrokeStyle(
                                    lineWidth: 4,
                                    lineCap: .round,
                                    lineJoin: .round
                                ))
                                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                        }
                    }
                    
                    // Prepare landmarks with z-order information
                    let sortedLandmarks = prepareLandmarksWithDepth(geometry: geometry)
                    
                    // Draw landmarks in z-order (from back to front)
                    ForEach(sortedLandmarks) { landmark in
                        ZStack {
                            // Outer glow effect
                            Circle()
                                .fill(landmark.style.color.opacity(0.4))
                                .frame(width: landmark.style.size + 4, height: landmark.style.size + 4)
                            
                            // Inner solid circle
                            Circle()
                                .fill(landmark.style.color)
                                .frame(width: landmark.style.size, height: landmark.style.size)
                                .shadow(color: Color.black.opacity(0.5), radius: 1, x: 0, y: 0)
                        }
                        .position(landmark.position)
                    }
                }
            } else {
                // Empty view when no pose is detected
                EmptyView()
            }
        }
    }
    
    // Helper function to prepare connections with depth information
    private func prepareConnectionsWithDepth(geometry: GeometryProxy) -> [Connection] {
        var connections: [Connection] = []
        
        for (groupIndex, group) in connectionGroups.enumerated() {
            for connection in group.connections {
                if connection.fromIndex < poseResults.count && connection.toIndex < poseResults.count {
                    let fromLandmark = poseResults[connection.fromIndex]
                    let toLandmark = poseResults[connection.toIndex]
                    
                    if fromLandmark.visibility > 0.2 && toLandmark.visibility > 0.2 {
                        // Calculate average z-value for the connection
                        let avgZ = (fromLandmark.z + toLandmark.z) / 2
                        
                        connections.append(Connection(
                            fromIndex: connection.fromIndex,
                            toIndex: connection.toIndex,
                            color: group.color,
                            zValue: avgZ,
                            groupIndex: groupIndex
                        ))
                    }
                }
            }
        }
        
        // Sort by z-value (smaller z is closer to camera)
        return connections.sorted()
    }
    
    // Helper function to prepare landmarks with depth information
    private func prepareLandmarksWithDepth(geometry: GeometryProxy) -> [DrawableLandmark] {
        var landmarks: [DrawableLandmark] = []
        
        for landmark in poseResults {
            if landmark.visibility > 0.3 {
                let style = landmarkStyle(for: landmark.id)
                let position = CGPoint(
                    x: landmark.x * geometry.size.width,
                    y: landmark.y * geometry.size.height
                )
                
                landmarks.append(DrawableLandmark(
                    originalIndex: landmark.id,
                    position: position,
                    style: style,
                    zValue: landmark.z
                ))
            }
        }
        
        // Sort by z-value (smaller z is closer to camera)
        return landmarks.sorted()
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

class WebSocketManager: ObservableObject {
    @Published var isConnected = false
    @Published var lastFeedback = ""
    @Published var lastScore: Int = 0
    private var socket: WebSocket?
    private var hasCompletedHandshake = false
    private var pingTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    
    // Callback for when a score is received
    var onScoreReceived: ((Int) -> Void)? = nil
    
    init() {
        setupSocket()
        setupAudioSession()
    }
    
    // Setup audio session for playing sounds
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    // Play different sounds based on score
    private func playSound(for score: Int) {
        guard audioPlayer == nil || !audioPlayer!.isPlaying else { return }
        
        var soundName = ""
        
        // Select sound based on score range
        switch score {
        case 0...30:
            soundName = "low_score"
        case 31...70:
            soundName = "mid_score"
        default:
            soundName = "high_score"
        }
        
        // Since we might not have the actual sound files, we'll use system sounds as fallback
        let systemSoundID: SystemSoundID
        switch score {
        case 0...30:
            systemSoundID = 1054 // Error sound
        case 31...70:
            systemSoundID = 1052 // Medium sound
        default:
            // Use a more exciting sound for high scores (celebration/achievement sound)
            systemSoundID = 1325 // Much louder achievement sound
            
            // For high scores, play the sound twice with a slight delay for emphasis
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AudioServicesPlaySystemSound(1325)
                
                // Add vibration for high scores
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            }
        }
        
        // Try to play from file first
        if let soundPath = Bundle.main.path(forResource: soundName, ofType: "mp3") {
            let url = URL(fileURLWithPath: soundPath)
            
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                
                // For high scores, increase volume to maximum
                if score > 70 {
                    audioPlayer?.volume = 1.0
                    
                    // Play it twice for emphasis if it's a custom sound
                    audioPlayer?.numberOfLoops = 1
                }
                
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            } catch {
                print("Failed to play sound: \(error)")
                // Fallback to system sound
                AudioServicesPlaySystemSound(systemSoundID)
            }
        } else {
            // If sound file not found, use system sound
            print("Sound file '\(soundName).mp3' not found, using system sound")
            AudioServicesPlaySystemSound(systemSoundID)
        }
    }
    
    func setupSocket() {
        // Use wss:// for secure or ws:// for non-secure
        // Make sure to use the correct path format for Socket.IO v4
        let url = URL(string: "ws://192.168.7.92:5001/socket.io/?EIO=4&transport=websocket")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        print("Attempting to connect to: \(url.absoluteString)")
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    func disconnect() {
        pingTimer?.invalidate()
        socket?.disconnect()
        socket = nil
    }
    
    // Send periodic pings to keep the connection alive
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func sendPing() {
        socket?.write(string: "2")
    }
    
    // Send a properly formatted Socket.IO packet
    private func sendSocketIOMessage(event: String, data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to serialize JSON")
            return
        }
        
        // Socket.IO v4 emit format: 42["event_name",data]
        let message = "42[\"" + event + "\"," + jsonString + "]"
        socket?.write(string: message)
        print("Sent Socket.IO message: \(event)")
    }
    
    // Process received score from server
    private func processScoreMessage(message: String) {
        // Parse the JSON to extract the score
        do {
            // First we need to extract the JSON part from the Socket.IO message
            if let dataStartIndex = message.range(of: "42[\"score\",")?.upperBound,
               let dataEndIndex = message.range(of: "]", options: .backwards)?.lowerBound {
                
                let jsonSubstring = message[dataStartIndex..<dataEndIndex]
                
                // Handle both formats: direct number or JSON object
                if let scoreValue = Int(jsonSubstring.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // Direct number format
                    updateScore(scoreValue)
                } else {
                    // JSON object format
                    if let data = jsonSubstring.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let score = json["score"] as? Int {
                        updateScore(score)
                    }
                }
            }
        } catch {
            print("Error parsing score message: \(error)")
        }
    }
    
    // Update score value and trigger callbacks
    private func updateScore(_ score: Int) {
        DispatchQueue.main.async {
            self.lastScore = score
            self.lastFeedback = "Received score: \(score)"
            
            // Play appropriate sound
            self.playSound(for: score)
            
            // Notify observer
            self.onScoreReceived?(score)
        }
    }
    
    func sendWorldKeypoints(landmarks: [PoseLandmark]) {
        // Only send if we are properly connected and handshake is complete
        guard let socket = socket, self.isConnected, hasCompletedHandshake, !landmarks.isEmpty else {
            return
        }
        
        // Format world keypoints data
        var keypointsArray: [Double] = []
        for landmark in landmarks {
            keypointsArray.append(Double(landmark.x))
            keypointsArray.append(Double(landmark.y))
            keypointsArray.append(Double(landmark.z))
            keypointsArray.append(Double(landmark.visibility))
        }
        
        let payload: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "landmarks": keypointsArray  // Simplified key name
        ]
        
        // Send with proper Socket.IO formatting
        sendSocketIOMessage(event: "pose_landmarks", data: payload)
    }
    
    func sendStopNotification() {
        guard isConnected, hasCompletedHandshake else {
            print("Cannot send notification: WebSocket not connected")
            return
        }
        
        // Create a simple notification payload
        let payload: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "action": "video_stopped",
            "client": "ios"
        ]
        
        // Send with proper Socket.IO formatting
        sendSocketIOMessage(event: "camera_action", data: payload)
        
        print("Sent camera stop notification to server")
        
        // Update the feedback
        DispatchQueue.main.async {
            self.lastFeedback = "Sent stop notification to server"
        }
    }
    
    func reconnect() {
        // Disconnect if already connected
        disconnect()
        
        // Update feedback
        DispatchQueue.main.async {
            self.lastFeedback = "Attempting to reconnect..."
        }
        
        // Reconnect after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupSocket()
        }
    }
}

// Handle WebSocket events
extension WebSocketManager: WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        switch event {
        case .connected:
            print("⭐ WebSocket: connected - waiting for Socket.IO handshake")
            
        case .disconnected(let reason, _):
            DispatchQueue.main.async {
                self.isConnected = false
                self.hasCompletedHandshake = false
                print("⭐ WebSocket: disconnected - \(reason)")
            }
            
            // Try to reconnect after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.socket?.connect()
            }
            
        case .text(let string):
            print("⭐ WebSocket received text: \(string)")
            
            // Parse Socket.IO protocol messages
            if string.hasPrefix("0{") {
                // Socket.IO handshake packet (Engine.IO OPEN packet)
                print("⭐ Socket.IO: Received Engine.IO handshake")
                
                // After receiving the Engine.IO handshake, we need to send
                // the Socket.IO connect packet to join the default namespace
                socket?.write(string: "40")  // "40" means Socket.IO CONNECT to namespace "/"
                print("⭐ Socket.IO: Sent connect packet to default namespace")
            }
            else if string.hasPrefix("40") || string.hasPrefix("40,") {
                // Socket.IO connect acknowledgment
                print("⭐ Socket.IO: Connection to namespace acknowledged")
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.hasCompletedHandshake = true
                    
                    // Start ping timer to keep connection alive
                    self.startPingTimer()
                    
                    // Now that we're connected to the namespace, we can send events
                    self.sendSocketIOMessage(event: "connect_ack", data: ["client": "ios"])
                }
            }
            else if string.hasPrefix("42[") {
                // Regular Socket.IO event
                if string.contains("score") {
                    // This is a score message from the server
                    self.processScoreMessage(message: string)
                } else if let startIndex = string.range(of: "[")?.upperBound,
                   let endIndex = string.range(of: "]", options: .backwards)?.lowerBound {
                    let content = String(string[startIndex..<endIndex])
                    DispatchQueue.main.async {
                        self.lastFeedback = content
                        print("⭐ Socket.IO message: \(content)")
                    }
                }
            }
            else if string == "2" {
                // Engine.IO PING message from server, respond with Engine.IO PONG
                print("⭐ Received Engine.IO ping, sending pong")
                socket?.write(string: "3")
            }
            else if string == "3" {
                // Engine.IO PONG message (response to our ping)
                print("⭐ Received Engine.IO pong")
            }
            else {
                // Unknown message
                print("⭐ Received unknown Socket.IO message format: \(string)")
            }
            
        case .binary(let data):
            print("WebSocket: received binary data: \(data.count) bytes")
            
        case .error(let error):
            DispatchQueue.main.async {
                self.isConnected = false
                self.hasCompletedHandshake = false
                print("WebSocket error: \(error?.localizedDescription ?? "unknown error")")
            }
            
        case .cancelled:
            DispatchQueue.main.async {
                self.isConnected = false
                self.hasCompletedHandshake = false
                print("WebSocket: cancelled")
            }
            
        case .ping, .pong, .viabilityChanged, .reconnectSuggested:
            // Handle these events if needed
            break
            
        case .peerClosed:
            DispatchQueue.main.async {
                self.isConnected = false
                self.hasCompletedHandshake = false
                print("WebSocket: peer closed")
            }
        }
    }
}
