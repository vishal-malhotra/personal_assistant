import Foundation
import Combine
import UserNotifications

public enum DownloadableModelType: String, CaseIterable, Identifiable {
    case llama = "Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    case whisper = "ggml-base.bin"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .llama: return "Llama 3.2 1B (Reasoning & JSON)"
        case .whisper: return "Whisper Multilingual Base (Hinglish STT)"
        }
    }
    
    public var downloadURL: URL {
        switch self {
        case .llama:
            return URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!
        case .whisper:
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!
        }
    }
    
    public var sizeMB: Double {
        switch self {
        case .llama: return 750.0
        case .whisper: return 142.0
        }
    }
}

/// Manages true iOS background downloading, caching, and lifecycle of on-device quantized GGUF LLM and Whisper STT models.
public final class ModelDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = ModelDownloadManager()
    public static let backgroundSessionIdentifier = "com.vishal.personalassistant.modeldownload"
    
    public static let defaultModelName = "Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    
    @Published public private(set) var isDownloaded: Bool = false
    @Published public private(set) var isWhisperDownloaded: Bool = false
    @Published public private(set) var isDownloading: Bool = false
    @Published public private(set) var activeDownloadingType: DownloadableModelType?
    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var progressStatusText: String = ""
    @Published public private(set) var errorMessage: String?
    
    public var backgroundCompletionHandler: (() -> Void)?
    
    private var downloadTask: URLSessionDownloadTask?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.shouldSetCookies = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    public var modelsDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let modelsDir = paths[0].appendingPathComponent("models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        return modelsDir
    }
    
    public var localModelURL: URL? {
        let fileURL = modelsDirectoryURL.appendingPathComponent(Self.defaultModelName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        if let bundledPath = Bundle.main.url(forResource: (Self.defaultModelName as NSString).deletingPathExtension, withExtension: "gguf") {
            return bundledPath
        }
        return nil
    }
    
    public override init() {
        super.init()
        checkModelStatus()
        reconnectActiveBackgroundTasks()
    }
    
    public func checkModelStatus() {
        if let url = localModelURL, FileManager.default.fileExists(atPath: url.path) {
            self.isDownloaded = true
        } else {
            self.isDownloaded = false
        }
        
        let whisperPath = modelsDirectoryURL.appendingPathComponent(DownloadableModelType.whisper.rawValue).path
        self.isWhisperDownloaded = FileManager.default.fileExists(atPath: whisperPath)
    }
    
    private func reconnectActiveBackgroundTasks() {
        urlSession.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            for task in tasks {
                if let download = task as? URLSessionDownloadTask, download.state == .running {
                    DispatchQueue.main.async {
                        self.downloadTask = download
                        self.isDownloading = true
                        self.progressStatusText = "Downloading model in background..."
                    }
                }
            }
        }
    }
    
    public func startDownload(type: DownloadableModelType = .llama) {
        guard !isDownloading else { return }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
        errorMessage = nil
        isDownloading = true
        activeDownloadingType = type
        downloadProgress = 0.0
        progressStatusText = "Starting background download of \(type.displayName)..."
        
        downloadTask = urlSession.downloadTask(with: type.downloadURL)
        downloadTask?.resume()
    }
    
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        activeDownloadingType = nil
        downloadProgress = 0.0
        progressStatusText = ""
    }
    
    public func deleteModel(type: DownloadableModelType = .llama) {
        let fileURL = modelsDirectoryURL.appendingPathComponent(type.rawValue)
        try? FileManager.default.removeItem(at: fileURL)
        checkModelStatus()
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let currentMB = Double(totalBytesWritten) / (1024.0 * 1024.0)
            let totalMB = Double(totalBytesExpectedToWrite) / (1024.0 * 1024.0)
            
            DispatchQueue.main.async {
                self.isDownloading = true
                self.downloadProgress = progress
                self.progressStatusText = String(format: "Downloading: %.1f MB / %.1f MB (%.0f%%)", currentMB, totalMB, progress * 100)
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let targetType = activeDownloadingType ?? .llama
        let destinationURL = modelsDirectoryURL.appendingPathComponent(targetType.rawValue)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                self.isDownloading = false
                self.activeDownloadingType = nil
                self.downloadProgress = 1.0
                self.checkModelStatus()
                self.progressStatusText = "\(targetType.displayName) ready for offline inference!"
            }
            
            sendCompletionNotification(for: targetType)
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.activeDownloadingType = nil
                self.errorMessage = "Failed to save model: \(error.localizedDescription)"
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.activeDownloadingType = nil
                self.errorMessage = "Background download failed: \(error.localizedDescription)"
            }
        }
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let handler = self.backgroundCompletionHandler {
                self.backgroundCompletionHandler = nil
                handler()
            }
        }
    }
    
    private func sendCompletionNotification(for type: DownloadableModelType) {
        let content = UNMutableNotificationContent()
        content.title = "Offline AI Model Ready"
        content.body = "\(type.displayName) is downloaded and ready for 100% offline intelligence."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "ModelDownloadComplete_\(type.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
