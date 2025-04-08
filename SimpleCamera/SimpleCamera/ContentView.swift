import SwiftUI
import AVFoundation
import MediaPipeTasksVision
import UIKit
import Starscream

// Hello
// MARK: - Content View
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var socketManager = WebSocketManager()
    @State private var isCameraActive = false
    @State private var showPermissionAlert = false
    @State private var lastScore: Int = 0
    @State private var showScoreIndicator = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                // Connection status indicator
                HStack {
                    Circle()
                        .fill(socketManager.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(socketManager.isConnected ? "Connected to Server" : "Not Connected")
                        .font(.caption)
                        .foregroundColor(.white)
                    Spacer()
                    
                    // Reconnect button
                    Button(action: {
                        socketManager.reconnect()
                    }) {
                        Text("Reconnect")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                // Score display
                if showScoreIndicator {
                    HStack {
                        Text("Score: \(socketManager.lastScore)")
                            .font(.headline)
                            .foregroundColor(scoreColor(for: socketManager.lastScore))
                            .padding(.vertical, 5)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .onAppear {
                        // Hide score after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                showScoreIndicator = false
                            }
                        }
                    }
                }
                
                // Feedback from server
                if !socketManager.lastFeedback.isEmpty {
                    Text("Feedback: \(socketManager.lastFeedback)")
                        .foregroundColor(.white)
                        .padding(.horizontal)
                }
                
                // Camera preview (only shown when active)
                if isCameraActive {
                    CameraPreviewView(session: cameraManager.session)
                        .cornerRadius(12)
                        .padding()
                        .transition(.opacity)
                        .overlay(
                            // Pose overlay view
                            PoseOverlayView(poseResults: cameraManager.poseResults)
                                .padding()
                        )
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
            return .red
        case 31...70:
            return .yellow
        default:
            return .green
        }
    }
    
    // Setup observer for score updates
    private func setupScoreObserver() {
        // Observe when score changes
        socketManager.onScoreReceived = { score in
            withAnimation {
                self.lastScore = score
                self.showScoreIndicator = true
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
                if let validPoseLandmarks = poseLandmarks {
                    self.poseResults = validPoseLandmarks
                }
                
                // Only send world landmarks if available
                if let validWorldLandmarks = worldLandmarks, !validWorldLandmarks.isEmpty {
                    self.socketManager?.sendWorldKeypoints(landmarks: validWorldLandmarks)
                }
                // No fallback to regular landmarks anymore
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
        modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task", inDirectory: "Models")
        
        if modelPath == nil {
            modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task")
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
                
                return (customLandmarks, customWorldLandmarks)
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
    
    // Check if we have valid landmarks to draw
    private func hasValidLandmarks() -> Bool {
        return !poseResults.isEmpty && 
               poseResults.count >= 33 && // MediaPipe Pose has 33 landmarks
               // Check if at least some key landmarks have decent visibility
               (poseResults[11].visibility > 0.5 || poseResults[12].visibility > 0.5)
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
            // Only draw if we have valid landmarks
            if hasValidLandmarks() {
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

// MARK: - Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#Preview {
    ContentView()
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
