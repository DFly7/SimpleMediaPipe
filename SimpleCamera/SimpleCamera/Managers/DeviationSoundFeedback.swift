import Foundation
import AVFoundation

/**
 * DeviationSoundFeedback provides real-time auditory feedback based on swing deviation metrics.
 *
 * This class plays different sounds based on the current deviation value. The sound characteristics
 * (type, volume, frequency) vary depending on the quality of the user's golf swing compared to a model swing.
 */
class DeviationSoundFeedback {
    // Thread that runs continuous sound feedback
    private var feedbackThread: Thread?
    
    // Flag to control whether the feedback thread should terminate
    private var shouldStopFeedback = false
    
    // Lock used to safely access and modify deviation values
    private let deviationLock = NSLock()
    
    // Current deviation value that determines sound characteristics
    private var currentDeviation: Float = 0.0
    
    // Flag to control whether sound feedback is enabled
    private var enableSoundFeedback = true
    
    // Flag to track if we've received any deviation data
    private var hasReceivedDeviation = false
    
    // Timestamp of the last deviation update
    private var lastDeviationTime: TimeInterval = 0
    
    // Audio session and player
    private var audioPlayer: AVAudioPlayer?
    
    // Initialize with audio session setup
    init() {
        setupAudioSession()
    }
    
    /**
     * Sets up the audio session for playback.
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
     * Update the current deviation value in a thread-safe manner.
     */
    func setDeviation(_ deviationValue: Float) {
        deviationLock.lock()
        currentDeviation = deviationValue
        hasReceivedDeviation = true
        lastDeviationTime = Date().timeIntervalSince1970
        deviationLock.unlock()
        
        // If we're not in continuous mode, play a sound immediately based on the new value
        if feedbackThread == nil || !feedbackThread!.isExecuting {
            playDeviationSound(deviationValue)
        }
    }
    
    /**
     * Retrieve the current deviation value in a thread-safe manner.
     */
    func getDeviation() -> Float {
        deviationLock.lock()
        let deviation = currentDeviation
        deviationLock.unlock()
        return deviation
    }
    
    /**
     * Check if we've received any deviation data and if it's still fresh.
     */
    private func hasRecentDeviation() -> Bool {
        deviationLock.lock()
        let hasData = hasReceivedDeviation
        let timeSinceLastUpdate = Date().timeIntervalSince1970 - lastDeviationTime
        deviationLock.unlock()
        
        // Consider data fresh if received in the last 3 seconds
        return hasData && timeSinceLastUpdate < 1.0
    }
    
    /**
     * Start the continuous sound feedback thread if not already running.
     */
    func startFeedback() {
        guard enableSoundFeedback else { return }
        
        // Check if the thread is already running
        if feedbackThread != nil && feedbackThread!.isExecuting {
            return  // Already running
        }
        
        // Reset the stop flag
        shouldStopFeedback = false
        
        // Create and start a thread for continuous feedback
        feedbackThread = Thread { [weak self] in
            self?.playContinuousFeedback()
        }
        feedbackThread?.start()
    }
    
    /**
     * Stop the continuous sound feedback thread.
     */
    func stopFeedback() {
        shouldStopFeedback = true
        // Thread will check this flag and terminate
    }
    
    /**
     * Enable or disable the continuous sound feedback.
     */
    func setEnabled(_ enabled: Bool) {
        enableSoundFeedback = enabled
        
        if !enabled {
            stopFeedback()
        } else if feedbackThread == nil || !feedbackThread!.isExecuting {
            startFeedback()
        }
    }
    
    /**
     * Play continuous sound feedback where tone quality changes with deviation.
     */
    private func playContinuousFeedback() {
        // Maximum deviation threshold before we consider it "very bad"
        let maxDeviation: Float = 0.9
        
        // Main feedback loop - runs until explicitly stopped
        while !shouldStopFeedback {
            // Only play if we have received some deviation data and it's recent
            if hasRecentDeviation() {
                // Get current deviation value in a thread-safe way
                let currentDeviation = getDeviation()
                
                // Convert raw deviation to a normalized value between 0.0-1.0
                let normDeviation = min(1.0, currentDeviation / maxDeviation)
                
                // Play sound based on deviation
                playDeviationSound(normDeviation)
                
                // Wait before next sound - depends on severity
                let waitTime: TimeInterval
                if normDeviation < 0.3 {
                    waitTime = 1.0  // Longer wait for good performance
                } else if normDeviation < 0.7 {
                    waitTime = 0.5  // Medium wait for moderate deviation
                } else {
                    waitTime = 0.3  // Short wait for severe deviation
                }
                
                // Sleep for the specified duration
                Thread.sleep(forTimeInterval: waitTime)
            } else {
                // If no recent deviation data, wait longer before checking again
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
    
    /**
     * Play a sound based on the given deviation value.
     */
    private func playDeviationSound(_ normDeviation: Float) {
        // Only proceed if sound feedback is enabled
        guard enableSoundFeedback else { return }
        
        // If there's already a sound playing, don't interrupt it
        if let player = audioPlayer, player.isPlaying {
            return
        }
        
        // Select sound and volume based on deviation
        var soundName: String
        var volume: Float
        
        if normDeviation < 0.3 {
            // Tier 1: Good performance - gentle feedback
            soundName = "Tink"
            volume = 0.3
        } else if normDeviation < 0.7 {
            // Tier 2: Moderate deviation - medium alert
            soundName = "Ping"
            volume = 0.5
        } else {
            // Tier 3: Poor performance - strong alert
            soundName = "Basso"
            volume = 0.8
        }
        
        // Play the selected sound
        if let soundURL = Bundle.main.url(forResource: soundName, withExtension: "aiff") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.volume = volume
                audioPlayer?.play()
            } catch {
                print("Failed to play sound \(soundName): \(error)")
                playSystemSound(for: normDeviation)
            }
        } else {
            // Fallback to system sounds if custom sounds are not found
            playSystemSound(for: normDeviation)
        }
    }
    
    /**
     * Play a system sound based on the given deviation value.
     */
    private func playSystemSound(for normDeviation: Float) {
        let systemSoundID: SystemSoundID
        
        if normDeviation < 0.3 {
            systemSoundID = 1054  // Subtle sound
        } else if normDeviation < 0.7 {
            systemSoundID = 1052  // Medium sound
        } else {
            // Use a more appropriate alarming sound for high deviation
            // 1073 = "Alert" - more attention-grabbing without being too jarring
            systemSoundID = 1073
        }
        
        AudioServicesPlaySystemSound(systemSoundID)
    }
    
    /**
     * Play a distinctive beep sound to indicate state transitions.
     */
    func playBeep() {
        AudioServicesPlaySystemSound(1307)  // Submarine sound
    }
} 
