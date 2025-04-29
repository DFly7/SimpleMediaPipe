import Foundation
import Starscream

/**
 * Protocol for socket connection events
 */
protocol SocketConnectionDelegate: AnyObject {
    func didConnect()
    func didCompleteHandshake()
    func didDisconnect()
    func didReceiveScore(_ score: Int)
    func didReceiveDeviation(_ deviationValue: Float)
    func didReceiveFeedback(_ feedback: String)
}

/**
 * SocketConnectionManager handles WebSocket connections with Socket.IO protocol support.
 *
 * This class is responsible for managing the WebSocket connection lifecycle,
 * handling the Socket.IO protocol handshake, sending formatted messages,
 * and processing received messages.
 */
class SocketConnectionManager: NSObject, WebSocketDelegate {
    weak var delegate: SocketConnectionDelegate?
    private var socket: WebSocket?
    private var pingTimer: Timer?
    
    init(delegate: SocketConnectionDelegate) {
        self.delegate = delegate
        super.init()
    }
    
    /**
     * Connects to a WebSocket server at the specified URL.
     */
    func connect(to url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        print("Attempting to connect to: \(url.absoluteString)")
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    /**
     * Disconnects from the WebSocket server.
     */
    func disconnect() {
        pingTimer?.invalidate()
        socket?.disconnect()
        socket = nil
    }
    
    /**
     * Sends a Socket.IO formatted message to the server.
     *
     * @param event The event name to send
     * @param data The data payload for the event
     */
    func sendSocketIOMessage(event: String, data: [String: Any]) {
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
     * Starts a timer to send periodic ping messages to maintain the connection.
     */
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    /**
     * Sends a ping message to the server.
     */
    private func sendPing() {
        socket?.write(string: "2")
    }
    
    /**
     * Processes a score message received from the server.
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
                    delegate?.didReceiveScore(scoreValue)
                } else {
                    // JSON object format
                    if let data = jsonSubstring.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let score = json["score"] as? Int {
                        delegate?.didReceiveScore(score)
                    }
                }
            }
        } catch {
            print("Error parsing score message: \(error)")
        }
    }
    
    /**
     * Processes a deviation message received from the server.
     */
    private func processDeviationMessage(message: String) {
        // Parse the JSON to extract the deviation value
        do {
            // First we need to extract the JSON part from the Socket.IO message
            if let dataStartIndex = message.range(of: "42[\"deviation\",")?.upperBound,
               let dataEndIndex = message.range(of: "]", options: .backwards)?.lowerBound {
                
                let jsonSubstring = message[dataStartIndex..<dataEndIndex]
                
                // Handle both formats: direct number or JSON object
                if let deviationValue = Float(jsonSubstring.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // Direct number format
                    delegate?.didReceiveDeviation(deviationValue)
                } else {
                    // JSON object format
                    if let data = jsonSubstring.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let deviation = json["value"] as? Float {
                        delegate?.didReceiveDeviation(deviation)
                    }
                }
            }
        } catch {
            print("Error parsing deviation message: \(error)")
        }
    }
    
    // MARK: - WebSocketDelegate
    
    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        switch event {
        case .connected:
            print("⭐ WebSocket: connected - waiting for Socket.IO handshake")
            
        case .disconnected(let reason, _):
            print("⭐ WebSocket: disconnected - \(reason)")
            delegate?.didDisconnect()
            
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
                
                delegate?.didConnect()
                delegate?.didCompleteHandshake()
                delegate?.didReceiveFeedback("Connected to pose server!")
                
                // Start ping timer to keep connection alive
                self.startPingTimer()
                
                // Now that we're connected to the namespace, we can send events
                self.sendSocketIOMessage(event: "connect_ack", data: ["client": "ios"])
            }
            else if string.hasPrefix("42[") {
                // Regular Socket.IO event
                if string.contains("score") {
                    // This is a score message from the server
                    self.processScoreMessage(message: string)
                } else if string.contains("deviation") {
                    // This is a deviation message from the server
                    self.processDeviationMessage(message: string)
                } else if let startIndex = string.range(of: "[")?.upperBound,
                   let endIndex = string.range(of: "]", options: .backwards)?.lowerBound {
                    let content = String(string[startIndex..<endIndex])
                    delegate?.didReceiveFeedback(content)
                    print("⭐ Socket.IO message: \(content)")
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
            print("WebSocket error: \(error?.localizedDescription ?? "unknown error")")
            delegate?.didDisconnect()
            
        case .cancelled:
            print("WebSocket: cancelled")
            delegate?.didDisconnect()
            
        case .ping, .pong, .viabilityChanged, .reconnectSuggested:
            // Handle these events if needed
            break
            
        case .peerClosed:
            print("WebSocket: peer closed")
            delegate?.didDisconnect()
        }
    }
} 