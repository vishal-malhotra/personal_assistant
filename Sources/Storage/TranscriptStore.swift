import Foundation

public struct MeetingRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let durationSeconds: TimeInterval
    public let rawTranscript: String
    public let payload: MeetingPayload
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        durationSeconds: TimeInterval,
        rawTranscript: String,
        payload: MeetingPayload
    ) {
        self.id = id
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.rawTranscript = rawTranscript
        self.payload = payload
    }
}

/// Secure local store for persisting completed meeting transcripts and summaries.
/// Applies NSFileProtectionComplete encryption to protect data at rest on-device.
public final class TranscriptStore: ObservableObject {
    public static let shared = TranscriptStore()
    
    @Published public private(set) var records: [MeetingRecord] = []
    
    private let fileManager = FileManager.default
    private let storeFileURL: URL
    
    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storeFileURL = docs.appendingPathComponent("encrypted_meeting_records.json")
        loadRecords()
    }
    
    public func saveRecord(_ record: MeetingRecord) {
        records.insert(record, at: 0)
        persistToDisk()
    }
    
    public func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        persistToDisk()
    }
    
    private func loadRecords() {
        guard fileManager.fileExists(atPath: storeFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeFileURL)
            let decoded = try JSONDecoder().decode([MeetingRecord].self, from: data)
            self.records = decoded
        } catch {
            print("[TranscriptStore] Failed to load records: \(error.localizedDescription)")
        }
    }
    
    private func persistToDisk() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: storeFileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("[TranscriptStore] Failed to persist records: \(error.localizedDescription)")
        }
    }
}
