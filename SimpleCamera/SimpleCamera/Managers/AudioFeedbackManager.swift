import Foundation
import AVFoundation

/**
 * AudioFeedbackManager handles playing sound effects based on score values.
 *
 * This class manages audio session setup, sound file loading, and playback of
 * appropriate sound effects for different score ranges.
 */
class AudioFeedbackManager {
    private var audioPlayer: AVAudioPlayer?
    
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
     * Plays a sound effect based on the score value.
     *
     * Different sounds are played for low, medium, and high scores,
     * with additional effects for high scores.
     *
     * @param score The numerical score value (0-100)
     */
    func playSound(for score: Int) {
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
} 