import Foundation
import Combine

/// Manages downloading, local caching, and lifecycle of on-device quantized GGUF LLM models.
public final class ModelDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = ModelDownloadManager()
    
    // Default optimized model for iPhone 12 Mini / A14 Bionic (4GB RAM)
    public static let defaultModelName = "Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    public static let defaultModelDownloadURL = URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!
    public static let defaultModelSizeMB: Double = 750.0
    
    @Published public private(set) var isDownloaded: Bool = false
    @Published public private(set) var isDownloading: Bool = false
    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var progressStatusText: String = ""
    @Published public private(set) var errorMessage: String?
    
    private var downloadTask: URLSessionDownloadTask?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
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
        
        // Also check if model was bundled with the app
        if let bundledPath = Bundle.main.url(forResource: (Self.defaultModelName as NSString).deletingPathExtension, withExtension: "gguf") {
            return bundledPath
        }
        
        return nil
    }
    
    public override init() {
        super.init()
        checkModelStatus()
    }
    
    public func checkModelStatus() {
        if let url = localModelURL, FileManager.default.fileExists(atPath: url.path) {
            self.isDownloaded = true
        } else {
            self.isDownloaded = false
        }
    }
    
    public func startDownload() {
        guard !isDownloading else { return }
        
        errorMessage = nil
        isDownloading = true
        downloadProgress = 0.0
        progressStatusText = "Connecting to Hugging Face..."
        
        downloadTask = urlSession.downloadTask(with: Self.defaultModelDownloadURL)
        downloadTask?.resume()
    }
    
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        progressStatusText = ""
    }
    
    public func deleteModel() {
        guard let url = localModelURL else { return }
        try? FileManager.default.removeItem(at: url)
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
                self.downloadProgress = progress
                self.progressStatusText = String(format: "Downloading: %.1f MB / %.1f MB (%.0f%%)", currentMB, totalMB, progress * 100)
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let destinationURL = modelsDirectoryURL.appendingPathComponent(Self.defaultModelName)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                self.isDownloading = false
                self.isDownloaded = true
                self.downloadProgress = 1.0
                self.progressStatusText = "Model ready for offline on-device AI!"
            }
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.errorMessage = "Failed to save model: \(error.localizedDescription)"
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
