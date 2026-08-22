import AVFoundation
import Combine
import Foundation

/// Manages the low-level AVAudioSession lifecycle, background audio modes,
/// interruptions (e.g. phone calls), and hardware audio route changes.
public final class AudioSessionManager: ObservableObject {
    public static let shared = AudioSessionManager()
    
    @Published public private(set) var isInterrupted: Bool = false
    @Published public private(set) var currentRouteName: String = "Built-in Microphone"
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationObservers()
    }
    
    /// Configures the AVAudioSession for robust background recording with Bluetooth and speaker mixing.
    public func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        // Category .playAndRecord enables simultaneous input capture & playback (e.g., audio chimes)
        // Options .allowBluetooth and .defaultToSpeaker guarantee proper I/O routing
        try session.setCategory(
            .playAndRecord,
            mode: .measurement, // .measurement minimizes Apple's system-level audio processing/filtering
            options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers]
        )
        
        // Prefer standard 16kHz or 48kHz sample rate suitable for ASR
        try session.setPreferredSampleRate(16000.0)
        try session.setPreferredIOBufferDuration(0.02) // 20ms buffer frames
        
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        updateCurrentRoute()
    }
    
    /// Deactivates the audio session gracefully to restore system audio routing.
    public func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AudioSessionManager] Warning: Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Interruptions & Route Changes
    
    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                self?.handleInterruption(notification: notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                self?.handleRouteChange(notification: notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        DispatchQueue.main.async {
            switch type {
            case .began:
                self.isInterrupted = true
                print("[AudioSessionManager] Audio session interrupted (e.g., incoming call).")
            case .ended:
                self.isInterrupted = false
                guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    try? self.configureAudioSession()
                }
                print("[AudioSessionManager] Audio session interruption ended.")
            @unknown default:
                break
            }
        }
    }
    
    private func handleRouteChange(notification: Notification) {
        updateCurrentRoute()
    }
    
    private func updateCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let inputName = session.currentRoute.inputs.first?.portName ?? "Default Input"
        DispatchQueue.main.async {
            self.currentRouteName = inputName
        }
    }
}
