import AVFoundation
import MediaPipeTasksVision
import SwiftUI

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var poseDetector: PoseDetector?
    
    @Published var poseResults: [PoseLandmark] = []
    private var currentFrameTimestamp: Int64 = 0
    
    // Add camera position property
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    
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
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
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
                connection.isVideoMirrored = self.cameraPosition == .front
            }
            
            self.session.commitConfiguration()
        }
    }
    
    // Add function to toggle camera
    func toggleCamera() {
        // Stop current session
        if session.isRunning {
            session.stopRunning()
        }
        
        // Remove existing inputs
        session.inputs.forEach { session.removeInput($0) }
        
        // Toggle camera position
        cameraPosition = cameraPosition == .back ? .front : .back
        
        // Setup with new camera position
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                return
            }
            
            self.session.beginConfiguration()
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            
            // Set video orientation if needed
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                // Mirror the video if using front camera
                connection.isVideoMirrored = self.cameraPosition == .front
            }
            
            self.session.commitConfiguration()
            
            // Restart session if it was running before
            if !self.session.isRunning {
                self.session.startRunning()
            }
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