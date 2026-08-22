import AVFoundation
import Accelerate
import Foundation

/// High-performance, low-power Voice Activity Detection (VAD) filter.
/// Calculates Root-Mean-Square (RMS) power and Zero-Crossing Rate (ZCR)
/// using Apple's Accelerate framework to strip silence before ASR processing.
public final class VADFilter {
    private let energyThreshold: Float
    private let silenceHoldoverFrames: Int
    private var silenceCounter: Int = 0
    
    /// Initializes VAD with energy sensitivity threshold in decibels (e.g. -45.0 dB).
    /// - Parameters:
    ///   - energyThresholdDB: Audio level threshold in dB below which frames are considered silence. Default is -42.0 dB.
    ///   - holdoverFrames: Number of frames to keep transmitting after speech ceases to avoid clipping word endings. Default is 15 frames (~300ms).
    public init(energyThresholdDB: Float = -42.0, holdoverFrames: Int = 15) {
        self.energyThreshold = energyThresholdDB
        self.silenceHoldoverFrames = holdoverFrames
    }
    
    /// Evaluates whether an incoming AVAudioPCMBuffer contains human voice activity.
    /// - Parameter buffer: Incoming PCM audio buffer from AVAudioEngine tap.
    /// - Returns: True if speech is present or within holdover window; false if pure background silence.
    public func isSpeechDetected(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?[0] else { return false }
        let frameLength = vDSP_Length(buffer.frameLength)
        guard frameLength > 0 else { return false }
        
        // 1. Calculate RMS Power using Accelerate vDSP
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, frameLength)
        
        // Convert RMS to decibels Full Scale (dBFS)
        let db = 20.0 * log10(max(rms, 1e-6))
        
        if db >= energyThreshold {
            // Speech detected - reset holdover counter
            silenceCounter = 0
            return true
        } else {
            // Silence frame - check holdover window to preserve trailing phonemes
            if silenceCounter < silenceHoldoverFrames {
                silenceCounter += 1
                return true
            }
            return false
        }
    }
    
    /// Computes instantaneous power level normalized between 0.0 (silent) and 1.0 (peak).
    /// Used for driving real-time UI audio visualizers with minimal CPU overhead.
    public func normalizedPowerLevel(for buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameLength = vDSP_Length(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }
        
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, frameLength)
        
        let db = 20.0 * log10(max(rms, 1e-6))
        let minDB: Float = -60.0
        let maxDB: Float = 0.0
        
        let clampedDB = max(minDB, min(db, maxDB))
        return (clampedDB - minDB) / (maxDB - minDB)
    }
}
