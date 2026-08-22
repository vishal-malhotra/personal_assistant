import ActivityKit
import Foundation

/// ActivityKit attributes defining the Live Activity presentation
/// on the Lock Screen and in the Dynamic Island during background recording.
public struct MeetingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var elapsedSeconds: Int
        public var isRecording: Bool
        public var audioLevel: Float
        
        public init(elapsedSeconds: Int, isRecording: Bool, audioLevel: Float = 0.0) {
            self.elapsedSeconds = elapsedSeconds
            self.isRecording = isRecording
            self.audioLevel = audioLevel
        }
    }
    
    public var sessionTitle: String
    
    public init(sessionTitle: String = "Voice Note / Meeting") {
        self.sessionTitle = sessionTitle
    }
}
