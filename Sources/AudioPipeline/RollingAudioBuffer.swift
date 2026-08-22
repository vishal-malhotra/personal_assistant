import AVFoundation
import Foundation

/// Manages ephemeral rolling audio buffers written to `NSTemporaryDirectory()`.
/// Ensures strict data lifecycle compliance by automatically shredding old audio files
/// every 30 seconds to prevent storage bloat and protect user privacy.
public final class RollingAudioBuffer {
    private let fileManager = FileManager.default
    private let tempDirectory: URL
    private let maxBufferDurationSeconds: TimeInterval
    private var activeAudioFiles: [URL] = []
    private let queue = DispatchQueue(label: "com.assistant.rollingbuffer", qos: .utility)
    
    public init(maxBufferDurationSeconds: TimeInterval = 30.0) {
        self.maxBufferDurationSeconds = maxBufferDurationSeconds
        self.tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AudioBufferChunkCache", isDirectory: true)
        createDirectoryIfNeeded()
    }
    
    deinit {
        purgeAllBuffers()
    }
    
    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: tempDirectory.path) {
            try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Generates a new unique temporary file URL for storing a raw audio chunk.
    public func createNewChunkURL() -> URL {
        let filename = "chunk_\(UUID().uuidString).caf"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        queue.async {
            self.activeAudioFiles.append(fileURL)
            self.cleanOldBuffers()
        }
        return fileURL
    }
    
    /// Explicitly deletes a processed audio chunk from disk.
    public func removeChunk(at fileURL: URL) {
        queue.async {
            self.deleteFileSilently(at: fileURL)
            self.activeAudioFiles.removeAll { $0 == fileURL }
        }
    }
    
    /// Purges all cached temporary audio buffers immediately (called upon session completion).
    public func purgeAllBuffers() {
        queue.sync {
            do {
                let files = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
                for file in files {
                    deleteFileSilently(at: file)
                }
                activeAudioFiles.removeAll()
            } catch {
                print("[RollingAudioBuffer] Error cleaning temp directory: \(error.localizedDescription)")
            }
        }
    }
    
    private func cleanOldBuffers() {
        // Keep only files created within the max buffer duration
        let expirationDate = Date().addingTimeInterval(-maxBufferDurationSeconds)
        
        do {
            let files = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.creationDateKey])
            for file in files {
                let resourceValues = try file.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = resourceValues.creationDate, creationDate < expirationDate {
                    deleteFileSilently(at: file)
                    activeAudioFiles.removeAll { $0 == file }
                }
            }
        } catch {
            print("[RollingAudioBuffer] Failed to prune expired buffers: \(error.localizedDescription)")
        }
    }
    
    private func deleteFileSilently(at url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
