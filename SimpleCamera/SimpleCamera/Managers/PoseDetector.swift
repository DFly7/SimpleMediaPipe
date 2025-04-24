import Foundation
import MediaPipeTasksVision
import AVFoundation

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