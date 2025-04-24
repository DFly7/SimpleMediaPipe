import Foundation
import Starscream
import AVFoundation
import Network
import ObjectiveC

/**
 * WebSocketManager is responsible for handling real-time communication with a pose-analysis server.
 * 
 * This class provides automatic server discovery using Bonjour/mDNS, fallback direct connections,
 * Socket.IO protocol support, and a callback system for pose scoring. It handles the complete
 * lifecycle of WebSocket connections including:
 * - Service discovery using both NWBrowser and NetServiceBrowser
 * - Automatic reconnection and fallback strategies
 * - Socket.IO protocol handshakes and message formatting
 * - Real-time pose landmark transmission
 * - Score reception and audio feedback
 */
class WebSocketManager: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var isConnected = false
    @Published var lastFeedback = ""
    @Published var lastScore: Int = 0
    @Published var discoveryStatus: String = "Not started"
    private var socket: WebSocket?
    private var hasCompletedHandshake = false
    private var pingTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var browser: NWBrowser?
    private var netServiceBrowser: NetServiceBrowser?
    private var discoveredServices: [NetService] = []
    private var resolvingService: NetService?
    private var serverEndpoint: NWEndpoint?
    private var discoveryTimer: Timer?
    private var defaultServerAddresses = ["192.168.7.92", "localhost", "127.0.0.1"]
    private var currentDefaultAddressIndex = 0
    private var isDiscoveryInProgress = false
    
    // Callback for when a score is received
    var onScoreReceived: ((Int) -> Void)? = nil
    
    /**
     * Initializes the WebSocketManager and starts the server discovery process.
     *
     * This constructor initializes the audio session and begins the server discovery
     * process immediately after initialization.
     */
    override init() {
        super.init()
        setupAudioSession()
        startDiscovery()
    }
    
    /**
     * Starts the service discovery process and sets up a fallback timer.
     *
     * This method initiates both NWBrowser and NetServiceBrowser discovery processes,
     * and sets a timeout after which direct connection attempts will be made if
     * service discovery fails.
     */
    private func startDiscovery() {
        isDiscoveryInProgress = true
        discoveryStatus = "Starting service discovery..."
        
        // Start the discovery process
        setupServiceDiscovery()
        
        // Set a timeout for discovery after which we'll try direct connection
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }
            
            DispatchQueue.main.async {
                self.discoveryStatus = "Discovery timed out, trying direct connection..."
                self.tryDirectConnection()
            }
        }
    }
    
    /**
     * Attempts direct connections to predefined server addresses.
     *
     * This method is called when service discovery fails or times out.
     * It tries to connect directly to addresses in the defaultServerAddresses array
     * one at a time with delays between attempts.
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
            setupSocket(with: url)
        }
        
        // Schedule next attempt if this one fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, !self.isConnected else { return }
            self.tryDirectConnection()
        }
    }
    
    /**
     * Sets up the audio session for playback.
     *
     * Configures the AVAudioSession to enable sound playback for score feedback.
     */
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    /**
     * Sets up service discovery using multiple methods.
     *
     * Initializes both NWBrowser (Network framework) and NetServiceBrowser (Bonjour)
     * to increase the chances of successful server discovery.
     */
    private func setupServiceDiscovery() {
        discoveryStatus = "Setting up discovery services..."
        
        // First try using Network framework
        setupNWBrowser()
        
        // Also set up NetServiceBrowser as a fallback
        setupNetServiceBrowser()
    }
    
    /**
     * Sets up NWBrowser for service discovery using the Network framework.
     *
     * This method configures and starts an NWBrowser that looks for services
     * with the type "_pose-server._tcp" in the "local" domain.
     */
    private func setupNWBrowser() {
        // Create a browser to look for our service
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        // Look for our service type
        let browserDescriptor = NWBrowser.Descriptor.bonjour(type: "_pose-server._tcp", domain: "local")
        browser = NWBrowser(for: browserDescriptor, using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.discoveryStatus = "NWBrowser is ready and searching"
                }
                print("NWBrowser is ready")
            case .failed(let error):
                DispatchQueue.main.async {
                    self.discoveryStatus = "NWBrowser failed: \(error)"
                }
                print("NWBrowser failed: \(error)")
                
                // Don't reconnect immediately as it could cause a loop
                // Just move to direct connection if not connected
                if !self.isConnected {
                    self.tryDirectConnection()
                }
            case .cancelled:
                DispatchQueue.main.async {
                    self.discoveryStatus = "NWBrowser cancelled"
                }
                print("NWBrowser cancelled")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self, !self.isConnected else { return }
            
            DispatchQueue.main.async {
                self.discoveryStatus = "Found \(results.count) services"
            }
            
            // Find the first available server
            if let firstResult = results.first {
                self.serverEndpoint = firstResult.endpoint
                self.connectToServer()
            }
        }
        
        browser?.start(queue: .main)
    }
    
    /**
     * Sets up NetServiceBrowser for Bonjour service discovery.
     *
     * Initializes and starts a NetServiceBrowser that searches for services
     * with the type "_pose-server._tcp." in the "local." domain.
     */
    private func setupNetServiceBrowser() {
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self
        netServiceBrowser?.searchForServices(ofType: "_pose-server._tcp.", inDomain: "local.")
    }
    
    /**
     * Attempts to connect to a discovered NetService.
     *
     * @param service The NetService to connect to
     */
    private func connectToNetService(_ service: NetService) {
        // Only try to connect if we're not already connected
        if !isConnected {
            DispatchQueue.main.async {
                self.lastFeedback = "Found server: \(service.name), resolving..."
            }
            
            // Store the service we're trying to resolve
            resolvingService = service
            service.delegate = self
            service.resolve(withTimeout: 5.0)
        }
    }
    
    /**
     * Attempts to connect to a server discovered via NWBrowser.
     *
     * This method converts an NWEndpoint to a NetService for resolution.
     */
    private func connectToServer() {
        guard let endpoint = serverEndpoint else {
            print("No server endpoint available")
            return
        }
        
        DispatchQueue.main.async {
            self.lastFeedback = "Found server, attempting to connect..."
        }
        
        // Convert the endpoint to a URL
        if case let NWEndpoint.service(name, type, domain, _) = endpoint {
            // Create a NetService and resolve it
            let service = NetService(domain: domain, type: type, name: name)
            service.delegate = self
            service.resolve(withTimeout: 5.0)
            
            // Store the service
            resolvingService = service
        }
    }
    
    /**
     * Sets up and initiates a WebSocket connection to the given URL.
     *
     * @param url The WebSocket server URL to connect to
     */
    private func setupSocket(with url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        DispatchQueue.main.async {
            self.lastFeedback = "Connecting to: \(url.absoluteString)"
            self.discoveryStatus = "Connecting to: \(url.host ?? "unknown"):\(url.port ?? 0)"
        }
        
        print("Attempting to connect to: \(url.absoluteString)")
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    /**
     * Disconnects from the server and stops all discovery processes.
     *
     * This method cleans up all resources including timers, sockets, and browsers.
     */
    func disconnect() {
        // Invalidate timers
        pingTimer?.invalidate()
        discoveryTimer?.invalidate()
        
        // Disconnect socket
        socket?.disconnect()
        socket = nil
        
        // Stop discovery
        browser?.cancel()
        netServiceBrowser?.stop()
        discoveredServices.removeAll()
        
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
     * Starts a timer to send periodic ping messages to the server.
     *
     * This method maintains the WebSocket connection by sending pings
     * at regular intervals to prevent timeout disconnections.
     */
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    /**
     * Sends a ping message to the server.
     *
     * This sends an Engine.IO ping (code "2") to the server to keep the connection alive.
     */
    private func sendPing() {
        socket?.write(string: "2")
    }
    
    /**
     * Sends a Socket.IO formatted message to the server.
     *
     * @param event The event name to send
     * @param data The data payload for the event
     */
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
    
    /**
     * Processes a score message received from the server.
     *
     * @param message The Socket.IO message containing score data
     */
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
            self.playSound(for: score)
            
            // Notify observer
            self.onScoreReceived?(score)
        }
    }
    
    /**
     * Sends pose landmarks to the server for analysis.
     *
     * @param landmarks Array of pose landmarks to send
     */
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
    
    /**
     * Sends a notification to the server that video capture has stopped.
     *
     * This informs the server that the client has stopped sending pose data.
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
        sendSocketIOMessage(event: "camera_action", data: payload)
        
        print("Sent camera stop notification to server")
        
        // Update the feedback
        DispatchQueue.main.async {
            self.lastFeedback = "Sent stop notification to server"
        }
    }
    
    /**
     * Disconnects and reconnects to the server.
     *
     * This method performs a clean disconnect followed by a new discovery process.
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
     * Plays a sound effect based on the score value.
     *
     * Different sounds are played for low, medium, and high scores,
     * with additional effects for high scores.
     *
     * @param score The numerical score value (0-100)
     */
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
    
    // MARK: - NetServiceBrowserDelegate
    
    /**
     * Called when a NetServiceBrowser discovers a service.
     *
     * @param browser The NetServiceBrowser that discovered the service
     * @param service The discovered NetService
     * @param moreComing Whether more results are forthcoming
     */
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        // Add the service to our list
        discoveredServices.append(service)
        
        DispatchQueue.main.async {
            self.discoveryStatus = "Found service: \(service.name)"
        }
        
        // Try to resolve and connect to this service
        connectToNetService(service)
    }
    
    /**
     * Called when a NetServiceBrowser removes a previously discovered service.
     *
     * @param browser The NetServiceBrowser that removed the service
     * @param service The removed NetService
     * @param moreComing Whether more results are forthcoming
     */
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        // Remove the service from our list
        if let index = discoveredServices.firstIndex(of: service) {
            discoveredServices.remove(at: index)
        }
        
        DispatchQueue.main.async {
            self.discoveryStatus = "Service removed: \(service.name)"
        }
    }
    
    /**
     * Called when a NetServiceBrowser stops searching.
     *
     * @param browser The NetServiceBrowser that stopped
     */
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        DispatchQueue.main.async {
            self.discoveryStatus = "Service browser stopped"
        }
    }
    
    /**
     * Called when a NetServiceBrowser fails to search.
     *
     * @param browser The NetServiceBrowser that failed
     * @param errorDict A dictionary containing information about the failure
     */
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        DispatchQueue.main.async {
            self.discoveryStatus = "NetServiceBrowser error: \(errorDict)"
        }
        print("NetServiceBrowser did not search: \(errorDict)")
        
        // If we couldn't search, try direct connection
        if !isConnected {
            tryDirectConnection()
        }
    }
    
    // MARK: - NetServiceDelegate
    
    /**
     * Called when a NetService successfully resolves its address.
     *
     * @param sender The NetService that was resolved
     */
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else {
            print("Failed to get hostname")
            
            DispatchQueue.main.async {
                self.discoveryStatus = "Failed to get hostname for service"
            }
            
            return
        }
        
        let port = sender.port
        
        DispatchQueue.main.async {
            self.discoveryStatus = "Resolved service: \(hostName):\(port)"
        }
        
        let urlString = "ws://\(hostName):\(port)/socket.io/?EIO=4&transport=websocket"
        if let url = URL(string: urlString) {
            setupSocket(with: url)
        }
    }
    
    /**
     * Called when a NetService fails to resolve its address.
     *
     * @param sender The NetService that failed to resolve
     * @param errorDict A dictionary containing information about the failure
     */
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("Failed to resolve: \(errorDict)")
        DispatchQueue.main.async {
            self.lastFeedback = "Failed to resolve service: \(errorDict)"
            self.discoveryStatus = "Resolution failed: \(errorDict)"
        }
        
        // Try the next available service if we have one
        if let service = discoveredServices.first(where: { $0 != sender }) {
            connectToNetService(service)
        } else if !isConnected {
            // If no more services to try, go to direct connection
            tryDirectConnection()
        }
    }
}

// MARK: - WebSocketDelegate

/**
 * Extension handling WebSocket events from the Starscream library.
 */
extension WebSocketManager: WebSocketDelegate {
    /**
     * Processes WebSocket events.
     *
     * @param event The WebSocket event to process
     * @param client The WebSocket client that generated the event
     */
    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        switch event {
        case .connected:
            print("⭐ WebSocket: connected - waiting for Socket.IO handshake")
            DispatchQueue.main.async {
                self.discoveryStatus = "WebSocket connected, waiting for handshake"
                
                // Cancel discovery timer since we've connected
                self.discoveryTimer?.invalidate()
            }
            
        case .disconnected(let reason, _):
            DispatchQueue.main.async {
                self.isConnected = false
                self.hasCompletedHandshake = false
                self.discoveryStatus = "WebSocket disconnected: \(reason)"
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
                DispatchQueue.main.async {
                    self.discoveryStatus = "Engine.IO handshake received"
                }
                
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
                    self.discoveryStatus = "Connected to Socket.IO server"
                    self.lastFeedback = "Connected to pose server!"
                    
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
