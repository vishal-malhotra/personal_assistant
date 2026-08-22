import AVFoundation
import Combine
import Foundation
import Speech

public enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case processing
    case error(String)
}

public struct RecognitionLanguage: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let flag: String
    
    public static let supported: [RecognitionLanguage] = [
        RecognitionLanguage(id: "en-IN", displayName: "Hinglish / English (India)", flag: "🇮🇳"),
        RecognitionLanguage(id: "hi-IN", displayName: "Hindi (हिंदी)", flag: "🇮🇳"),
        RecognitionLanguage(id: "en-US", displayName: "English (US)", flag: "🇺🇸")
    ]
}

/// Continuous multi-speaker on-device Speech-to-Text service.
/// Streams continuous PCM audio into SFSpeechRecognizer and accumulates all speaker dialogue turns without dropping audio across pauses.
public final class SpeechRecognitionService: NSObject, ObservableObject {
    public static let shared = SpeechRecognitionService()
    
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var liveTranscript: String = ""
    @Published public private(set) var finalizedTranscript: String = ""
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var sessionDuration: TimeInterval = 0.0
    @Published public private(set) var lastSessionAudioFileURL: URL?
    
    @Published public var selectedLocaleIdentifier: String = "en-IN" {
        didSet {
            self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: selectedLocaleIdentifier))
        }
    }
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionAudioFile: AVAudioFile?
    
    private let vadFilter = VADFilter(energyThresholdDB: -45.0)
    private let rollingBuffer = RollingAudioBuffer(maxBufferDurationSeconds: 30.0)
    
    private var segments: [String] = []
    private var currentLiveSegment: String = ""
    private var cycleTimer: Timer?
    private var durationTimer: Timer?
    private var startTime: Date?
    
    private let cycleIntervalSeconds: TimeInterval = 40.0
    
    public override init() {
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: selectedLocaleIdentifier))
        if self.speechRecognizer == nil {
            self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        }
    }
    
    // MARK: - Permissions
    
    public static func requestPermissions() async -> (micAuthorized: Bool, speechAuthorized: Bool) {
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        return (micGranted, speechStatus)
    }
    
    // MARK: - Session Lifecycle
    
    public func startRecording() throws {
        guard state == .idle || state == .paused else { return }
        
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: selectedLocaleIdentifier))
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("On-device speech recognizer is currently unavailable for \(selectedLocaleIdentifier).")
            return
        }
        
        try AudioSessionManager.shared.configureAudioSession()
        
        liveTranscript = ""
        finalizedTranscript = ""
        currentLiveSegment = ""
        segments.removeAll()
        sessionDuration = 0.0
        startTime = Date()
        
        let tempAudioURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("session_\(UUID().uuidString).caf")
        self.lastSessionAudioFileURL = tempAudioURL
        
        try startAudioEngineAndRecognitionCycle(outputAudioURL: tempAudioURL)
        
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            self.sessionDuration = Date().timeIntervalSince(start)
        }
        
        state = .recording
    }
    
    public func stopRecording() -> String {
        guard state == .recording || state == .paused else {
            return getFullTranscript()
        }
        
        state = .processing
        
        durationTimer?.invalidate()
        durationTimer = nil
        cycleTimer?.invalidate()
        cycleTimer = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        sessionAudioFile = nil
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        
        AudioSessionManager.shared.deactivateAudioSession()
        rollingBuffer.purgeAllBuffers()
        
        if !currentLiveSegment.isEmpty {
            segments.append(currentLiveSegment)
            currentLiveSegment = ""
        }
        
        let fullText = getFullTranscript()
        self.finalizedTranscript = fullText
        self.liveTranscript = fullText
        audioLevel = 0.0
        state = .idle
        
        return fullText
    }
    
    private func getFullTranscript() -> String {
        var allParts = segments
        if !currentLiveSegment.isEmpty && !allParts.contains(currentLiveSegment) {
            allParts.append(currentLiveSegment)
        }
        let joined = allParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.isEmpty && !liveTranscript.isEmpty {
            return liveTranscript
        }
        return joined
    }
    
    public func cleanupLastSessionAudio() {
        if let url = lastSessionAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
            lastSessionAudioFileURL = nil
        }
    }
    
    // MARK: - Rolling Recognition Cycle
    
    private func startAudioEngineAndRecognitionCycle(outputAudioURL: URL) throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        self.sessionAudioFile = try? AVAudioFile(forWriting: outputAudioURL, settings: recordingFormat.settings)
        
        try startRecognitionTask()
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
            guard let self = self else { return }
            
            // 1. Write buffer to disk for high-accuracy Whisper pass
            try? self.sessionAudioFile?.write(from: buffer)
            
            // 2. Audio level meter for UI
            let level = self.vadFilter.normalizedPowerLevel(for: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
            }
            
            // 3. Unconditionally feed all PCM buffers into SFSpeechRecognizer to avoid truncating pauses between speakers
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        scheduleNextCycleTimer()
    }
    
    private func startRecognitionTask() throws {
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        
        self.recognitionRequest = request
        
        guard let recognizer = self.speechRecognizer else { return }
        
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let latestSegment = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.currentLiveSegment = latestSegment
                    let combined = self.getFullTranscript()
                    self.liveTranscript = combined
                }
                
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.segments.append(latestSegment)
                        self.currentLiveSegment = ""
                        try? self.startRecognitionTask()
                    }
                }
            }
            
            if let error = error as NSError?, error.code != 216 && self.state == .recording {
                // If speech recognizer pauses or finishes on long silence, instantly refresh task
                DispatchQueue.main.async {
                    if !self.currentLiveSegment.isEmpty {
                        self.segments.append(self.currentLiveSegment)
                        self.currentLiveSegment = ""
                    }
                    try? self.startRecognitionTask()
                }
            }
        }
    }
    
    private func scheduleNextCycleTimer() {
        cycleTimer?.invalidate()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: cycleIntervalSeconds, repeats: false) { [weak self] _ in
            self?.performRollingCycleTransition()
        }
    }
    
    private func performRollingCycleTransition() {
        guard state == .recording else { return }
        
        if !currentLiveSegment.isEmpty {
            segments.append(currentLiveSegment)
            currentLiveSegment = ""
        }
        
        do {
            try startRecognitionTask()
            scheduleNextCycleTimer()
        } catch {
            print("[SpeechRecognitionService] Refresh cycle note: \(error.localizedDescription)")
        }
    }
}
