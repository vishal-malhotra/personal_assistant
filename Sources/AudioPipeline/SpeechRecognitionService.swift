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

/// Robust on-device Speech-to-Text service supporting Hinglish, Hindi, and English with audio caching for Whisper refinement.
/// Preserves the entire accumulated conversation history without dropping early speech chunks.
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
    
    private let vadFilter = VADFilter(energyThresholdDB: -42.0)
    private let rollingBuffer = RollingAudioBuffer(maxBufferDurationSeconds: 30.0)
    
    private var accumulatedSegments: [String] = []
    private var currentSegmentText: String = ""
    private var cycleTimer: Timer?
    private var durationTimer: Timer?
    private var startTime: Date?
    
    private let cycleIntervalSeconds: TimeInterval = 45.0
    
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
        currentSegmentText = ""
        accumulatedSegments.removeAll()
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
            return fullCombinedTranscript()
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
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        AudioSessionManager.shared.deactivateAudioSession()
        rollingBuffer.purgeAllBuffers()
        
        if !currentSegmentText.isEmpty {
            accumulatedSegments.append(currentSegmentText)
            currentSegmentText = ""
        }
        
        let completed = fullCombinedTranscript()
        self.finalizedTranscript = completed
        self.liveTranscript = completed
        audioLevel = 0.0
        state = .idle
        
        return completed
    }
    
    private func fullCombinedTranscript() -> String {
        var allParts = accumulatedSegments
        if !currentSegmentText.isEmpty && !allParts.contains(currentSegmentText) {
            allParts.append(currentSegmentText)
        }
        let merged = allParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if merged.isEmpty && !liveTranscript.isEmpty {
            return liveTranscript
        }
        return merged
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
            
            try? self.sessionAudioFile?.write(from: buffer)
            
            let level = self.vadFilter.normalizedPowerLevel(for: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
            }
            
            if self.vadFilter.isSpeechDetected(in: buffer) {
                self.recognitionRequest?.append(buffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        scheduleNextCycleTimer()
    }
    
    private func startRecognitionTask() throws {
        recognitionTask?.cancel()
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
                    self.currentSegmentText = latestSegment
                    let combined = self.fullCombinedTranscript()
                    self.liveTranscript = combined
                }
            }
            
            if let error = error as NSError?, error.code != 216 {
                print("[SpeechRecognitionService] Task note: \(error.localizedDescription)")
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
        
        if !currentSegmentText.isEmpty {
            accumulatedSegments.append(currentSegmentText)
            currentSegmentText = ""
        }
        
        do {
            try startRecognitionTask()
            scheduleNextCycleTimer()
        } catch {
            print("[SpeechRecognitionService] Error refreshing cycle: \(error.localizedDescription)")
        }
    }
}
