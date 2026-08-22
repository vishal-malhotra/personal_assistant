import XCTest
@testable import PersonalAssistant

final class PersonalAssistantTests: XCTestCase {
    
    // MARK: - Prompt Builder Tests
    
    func testPromptBuilderAnchorsDateAndTokens() {
        let transcript = "Vishal and Sarah agreed to meet on Thursday at 3:00 PM."
        let fixedDate = Date(timeIntervalSince1970: 1787356800) // Aug 22, 2026 approx
        let tz = TimeZone(identifier: "America/New_York")!
        
        let prompt = PromptBuilder.buildPrompt(
            transcript: transcript,
            referenceDate: fixedDate,
            timeZone: tz
        )
        
        XCTAssertTrue(prompt.contains("<|begin_of_text|>"))
        XCTAssertTrue(prompt.contains("<|start_header_id|>system<|end_header_id|>"))
        XCTAssertTrue(prompt.contains("Timezone: America/New_York"))
        XCTAssertTrue(prompt.contains(transcript))
        XCTAssertTrue(prompt.contains("<|start_header_id|>assistant<|end_header_id|>"))
    }
    
    // MARK: - English NLP & Extraction Tests
    
    func testEnglishMeetingExtraction() async throws {
        let transcript = "Let's schedule a backend architecture review meeting with Sarah tomorrow at 3:00 PM, and remind me to prepare the slides by 9:00 AM."
        
        let payload = try await ModelManager.shared.processTranscript(transcript)
        
        XCTAssertFalse(payload.meetingSummary.isEmpty)
        XCTAssertFalse(payload.dialogueTurns.isEmpty)
        XCTAssertFalse(payload.actionItems.isEmpty)
        
        // Assert calendar event and reminder extraction
        XCTAssertFalse(payload.calendarEvents.isEmpty, "Calendar event should be extracted for 'schedule a review meeting'")
        XCTAssertFalse(payload.reminders.isEmpty, "Reminder should be extracted for 'remind me to prepare slides'")
    }
    
    // MARK: - Hinglish & Hindi Extraction Tests
    
    func testHinglishMeetingAndDateExtraction() async throws {
        let transcript = "Rahul, kal shaam ko 5 baje client meeting rakh lete hain, aur mujhe yaad dilana ki kal subah 10 baje slides bhejna hai. Yeh final hai."
        
        let payload = try await ModelManager.shared.processTranscript(transcript)
        
        XCTAssertFalse(payload.meetingSummary.isEmpty)
        XCTAssertFalse(payload.dialogueTurns.isEmpty)
        XCTAssertFalse(payload.keyDecisions.isEmpty)
        
        // Assert calendar event for "kal shaam ko 5 baje"
        XCTAssertFalse(payload.calendarEvents.isEmpty, "Calendar event should be extracted for 'kal shaam ko 5 baje'")
        if let event = payload.calendarEvents.first {
            XCTAssertEqual(event.time, "05:00 PM")
            XCTAssertNotNil(event.targetStartDate())
        }
        
        // Assert reminder for "kal subah 10 baje"
        XCTAssertFalse(payload.reminders.isEmpty, "Reminder should be extracted for 'kal subah 10 baje'")
        if let reminder = payload.reminders.first {
            XCTAssertEqual(reminder.time, "10:00 AM")
            XCTAssertNotNil(reminder.targetDueDate())
        }
    }
    
    // MARK: - Zero Intent Validation (No Hallucinations)
    
    func testZeroSchedulingIntentProducesNoEvents() async throws {
        let transcript = "The weather today is really nice and we went for a walk in the garden."
        
        let payload = try await ModelManager.shared.processTranscript(transcript)
        
        XCTAssertTrue(payload.calendarEvents.isEmpty, "No calendar events should be extracted for casual talk")
        XCTAssertTrue(payload.reminders.isEmpty, "No reminders should be extracted for casual talk")
    }
    
    // MARK: - JSON Schema & EventKit Model Tests
    
    func testJSONDecodingMatchesEventKitSchema() throws {
        let json = """
        {
          "meeting_summary": "Testing summary generation.",
          "key_decisions": ["Approved load testing"],
          "action_items": ["Action item 1"],
          "dialogue_turns": [
            { "speaker": "Vishal", "text": "Let's review the API." }
          ],
          "calendar_events": [
            {
              "title": "Strategy Sync",
              "date": "2026-08-27",
              "time": "03:00 PM",
              "attendees": ["Vishal", "Sarah"]
            }
          ],
          "reminders": [
            {
              "title": "Send Mockups",
              "due_date": "2026-08-23",
              "time": "09:00 AM"
            }
          ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let payload = try JSONDecoder().decode(MeetingPayload.self, from: data)
        
        XCTAssertEqual(payload.meetingSummary, "Testing summary generation.")
        XCTAssertEqual(payload.keyDecisions.count, 1)
        XCTAssertEqual(payload.dialogueTurns.count, 1)
        XCTAssertEqual(payload.calendarEvents.count, 1)
        XCTAssertEqual(payload.reminders.count, 1)
        
        let event = payload.calendarEvents[0]
        XCTAssertEqual(event.title, "Strategy Sync")
        XCTAssertNotNil(event.targetStartDate())
        
        let reminder = payload.reminders[0]
        XCTAssertEqual(reminder.title, "Send Mockups")
        XCTAssertNotNil(reminder.targetDueDate())
    }
    
    // MARK: - Whisper & Model Downloader URL Tests
    
    func testDownloadableModelURLs() {
        XCTAssertEqual(DownloadableModelType.llama.sizeMB, 750.0)
        XCTAssertEqual(DownloadableModelType.whisper.sizeMB, 142.0)
        XCTAssertTrue(DownloadableModelType.llama.downloadURL.absoluteString.contains("huggingface.co"))
        XCTAssertTrue(DownloadableModelType.whisper.downloadURL.absoluteString.contains("huggingface.co"))
    }
    
    func testRollingAudioBufferPurge() {
        let buffer = RollingAudioBuffer(maxBufferDurationSeconds: 1.0)
        let chunk1 = buffer.createNewChunkURL()
        XCTAssertTrue(chunk1.path.contains("AudioBufferChunkCache"))
        
        buffer.purgeAllBuffers()
    }
}
