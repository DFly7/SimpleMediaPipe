import Foundation
import Starscream
import AVFoundation
import Network
import ObjectiveC

/**
 * WebSocketManager is responsible for handling real-time communication with a pose-analysis server.
 * 
 * This class provides automatic server discovery using Bonjour/mDNS, fallback direct connections,
 * Socket.IO protocol support, and a callback system for pose scoring.
 */
class WebSocketManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var lastFeedback = ""
    @Published var lastScore: Int = 0
    @Published var discoveryStatus: String = "Not started"
    
    // Private properties
    private var socket: WebSocket?
    private var hasCompletedHandshake = false
    private var pingTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var defaultServerAddresses = ["10.138.161.105", "192.168.7.92", "localhost", "127.0.0.1"]
    private var currentDefaultAddressIndex = 0
    private var isDiscoveryInProgress = false
    
    // Service discovery components
    private lazy var serviceDiscoveryManager = ServiceDiscoveryManager(delegate: self)
    
    // WebSocket connection components
    private lazy var socketConnectionManager = SocketConnectionManager(delegate: self)
    
    // Audio feedback component
    private lazy var audioFeedbackManager = AudioFeedbackManager()
    
    // Callback for when a score is received
    var onScoreReceived: ((Int) -> Void)? = nil
    
    /**
     * Initializes the WebSocketManager and starts the server discovery process.
     */
    override init() {
        super.init()
        startDiscovery()
    }
    
    /**
     * Starts the service discovery process.
     */
    private func startDiscovery() {
        isDiscoveryInProgress = true
        discoveryStatus = "Starting service discovery..."
        
        // Start the discovery process
        serviceDiscoveryManager.startDiscovery()
        
        // Set a timeout for discovery after which we'll try direct connection
        serviceDiscoveryManager.setDiscoveryTimeout(timeInterval: 5.0) { [weak self] in
            guard let self = self, !self.isConnected else { return }
            
            DispatchQueue.main.async {
                self.discoveryStatus = "Discovery timed out, trying direct connection..."
                self.tryDirectConnection()
            }
        }
    }
    
    /**
     * Attempts direct connections to predefined server addresses.
     */
    private func tryDirectConnection() {
        guard currentDefaultAddressIndex < defaultServerAddresses.count, !isConnected else { return }
        
        let serverAddress = defaultServerAddresses[currentDefaultAddressIndex]
        currentDefaultAddressIndex += 1
        
        DispatchQueue.main.async {
            self.lastFeedback = "Trying direct connection to \(serverAddress)..."
        }
        
        let urlString = "ws://\(serverAddress):5001/socket.io/?EIO=4&transport=websocket"
        if let url = URL(string: urlString) {
            socketConnectionManager.connect(to: url)
        }
        
        // Schedule next attempt if this one fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, !self.isConnected else { return }
            self.tryDirectConnection()
        }
    }
    
    /**
     * Disconnects from the server and stops all discovery processes.
     */
    func disconnect() {
        // Invalidate timers
        pingTimer?.invalidate()
        
        // Disconnect services
        socketConnectionManager.disconnect()
        serviceDiscoveryManager.stopDiscovery()
        
        // Reset flags
        isDiscoveryInProgress = false
        currentDefaultAddressIndex = 0
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.hasCompletedHandshake = false
            self.discoveryStatus = "Disconnected"
        }
    }
    
    /**
     * Sends pose landmarks to the server for analysis.
     *
     * @param landmarks Array of pose landmarks to send
     */
    func sendWorldKeypoints(landmarks: [PoseLandmark]) {
        // Only send if we are properly connected and handshake is complete
        guard isConnected, hasCompletedHandshake, !landmarks.isEmpty else {
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
        socketConnectionManager.sendSocketIOMessage(event: "pose_landmarks", data: payload)
    }
    
    /**
     * Sends a notification to the server that video capture has stopped.
     */
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
        socketConnectionManager.sendSocketIOMessage(event: "camera_action", data: payload)
        
        print("Sent camera stop notification to server")
        
        // Update the feedback
        DispatchQueue.main.async {
            self.lastFeedback = "Sent stop notification to server"
        }
    }
    
    /**
     * Disconnects and reconnects to the server.
     */
    func reconnect() {
        disconnect()
        
        DispatchQueue.main.async {
            self.discoveryStatus = "Reconnecting..."
            self.lastFeedback = "Reconnecting..."
        }
        
        // Start discovery process again
        startDiscovery()
    }
    
    /**
     * Updates the score value and triggers callbacks and sound feedback.
     *
     * @param score The numerical score value (0-100)
     */
    private func updateScore(_ score: Int) {
        DispatchQueue.main.async {
            self.lastScore = score
            self.lastFeedback = "Received score: \(score)"
            
            // Play appropriate sound
            self.audioFeedbackManager.playSound(for: score)
            
            // Notify observer
            self.onScoreReceived?(score)
        }
    }
}

// MARK: - ServiceDiscoveryDelegate

extension WebSocketManager: ServiceDiscoveryDelegate {
    func didFindServer(at url: URL) {
        socketConnectionManager.connect(to: url)
    }
    
    func didUpdateDiscoveryStatus(_ status: String) {
        DispatchQueue.main.async {
            self.discoveryStatus = status
        }
    }
}

// MARK: - SocketConnectionDelegate

extension WebSocketManager: SocketConnectionDelegate {
    func didConnect() {
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }
    
    func didCompleteHandshake() {
        DispatchQueue.main.async {
            self.hasCompletedHandshake = true
        }
    }
    
    func didDisconnect() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.hasCompletedHandshake = false
        }
    }
    
    func didReceiveScore(_ score: Int) {
        updateScore(score)
    }
    
    func didReceiveFeedback(_ feedback: String) {
        DispatchQueue.main.async {
            self.lastFeedback = feedback
        }
    }
} 
