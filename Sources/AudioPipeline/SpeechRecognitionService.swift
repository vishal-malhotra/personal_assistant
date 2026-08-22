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

/// Robust on-device Speech-to-Text service.
/// Uses Apple's native SFSpeechRecognizer with `requiresOnDeviceRecognition = true`.
/// Seamlessly overcomes the ~60-second iOS SFSpeechRecognizer timeout via automated 45-second rolling cycles.
public final class SpeechRecognitionService: NSObject, ObservableObject {
    public static let shared = SpeechRecognitionService()
    
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var liveTranscript: String = ""
    @Published public private(set) var finalizedTranscript: String = ""
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var sessionDuration: TimeInterval = 0.0
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let vadFilter = VADFilter(energyThresholdDB: -42.0)
    private let rollingBuffer = RollingAudioBuffer(maxBufferDurationSeconds: 30.0)
    
    private var segmentTextBuffer: String = ""
    private var cycleTimer: Timer?
    private var durationTimer: Timer?
    private var startTime: Date?
    
    private let cycleIntervalSeconds: TimeInterval = 45.0 // Reconnect recognizer every 45s before 60s timeout
    
    public override init() {
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
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
    
    /// Begins recording and real-time offline transcription.
    public func startRecording() throws {
        guard state == .idle || state == .paused else { return }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("On-device speech recognizer is currently unavailable.")
            return
        }
        
        guard recognizer.supportsOnDeviceRecognition else {
            state = .error("This device or locale does not support offline speech recognition.")
            return
        }
        
        try AudioSessionManager.shared.configureAudioSession()
        
        liveTranscript = ""
        finalizedTranscript = ""
        segmentTextBuffer = ""
        sessionDuration = 0.0
        startTime = Date()
        
        try startAudioEngineAndRecognitionCycle()
        
        // Start duration timer for UI
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            self.sessionDuration = Date().timeIntervalSince(start)
        }
        
        state = .recording
    }
    
    /// Stops the recording session, finalizes the full transcript, and purges all temporary audio caches.
    public func stopRecording() -> String {
        guard state == .recording || state == .paused else { return finalizedTranscript }
        
        state = .processing
        
        durationTimer?.invalidate()
        durationTimer = nil
        cycleTimer?.invalidate()
        cycleTimer = nil
        
        // Stop audio hardware
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        AudioSessionManager.shared.deactivateAudioSession()
        rollingBuffer.purgeAllBuffers()
        
        // Consolidate final transcript
        if !segmentTextBuffer.isEmpty {
            if finalizedTranscript.isEmpty {
                finalizedTranscript = segmentTextBuffer
            } else {
                finalizedTranscript += " " + segmentTextBuffer
            }
        }
        
        let completedTranscript = finalizedTranscript
        audioLevel = 0.0
        state = .idle
        
        return completedTranscript
    }
    
    // MARK: - Rolling Recognition Cycle (Solving Apple 60s Limit)
    
    private func startAudioEngineAndRecognitionCycle() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        try startRecognitionTask()
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
            guard let self = self else { return }
            
            // 1. Calculate live audio level for UI visualizer
            let level = self.vadFilter.normalizedPowerLevel(for: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
            }
            
            // 2. VAD: Only pass audio to recognizer if voice activity is detected
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
        request.requiresOnDeviceRecognition = true // Guarantees 100% offline & zero cloud egress
        request.taskHint = .dictation
        
        self.recognitionRequest = request
        
        guard let recognizer = self.speechRecognizer else { return }
        
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let latestSegment = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.segmentTextBuffer = latestSegment
                    if self.finalizedTranscript.isEmpty {
                        self.liveTranscript = latestSegment
                    } else {
                        self.liveTranscript = self.finalizedTranscript + " " + latestSegment
                    }
                }
            }
            
            if let error = error as NSError?, error.code != 216 { // 216 is expected cancel code on cycle switch
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
        
        // Commit current segment to finalized transcript
        if !segmentTextBuffer.isEmpty {
            if finalizedTranscript.isEmpty {
                finalizedTranscript = segmentTextBuffer
            } else {
                finalizedTranscript += " " + segmentTextBuffer
            }
            segmentTextBuffer = ""
        }
        
        // Seamlessly start fresh recognition task without stopping the audio engine
        do {
            try startRecognitionTask()
            scheduleNextCycleTimer()
            print("[SpeechRecognitionService] Completed seamless 45s recognition cycle refresh.")
        } catch {
            print("[SpeechRecognitionService] Error refreshing cycle: \(error.localizedDescription)")
        }
    }
}
