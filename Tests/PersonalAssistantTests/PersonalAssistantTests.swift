import XCTest
@testable import PersonalAssistant

final class PersonalAssistantTests: XCTestCase {
    
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
    
    func testJSONDecodingMatchesEventKitSchema() throws {
        let json = """
        {
          "meeting_summary": "Testing summary generation.",
          "action_items": ["Action item 1"],
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
        XCTAssertEqual(payload.calendarEvents.count, 1)
        XCTAssertEqual(payload.reminders.count, 1)
        
        let event = payload.calendarEvents[0]
        XCTAssertEqual(event.title, "Strategy Sync")
        XCTAssertNotNil(event.targetStartDate())
        
        let reminder = payload.reminders[0]
        XCTAssertEqual(reminder.title, "Send Mockups")
        XCTAssertNotNil(reminder.targetDueDate())
    }
    
    func testRollingAudioBufferPurge() {
        let buffer = RollingAudioBuffer(maxBufferDurationSeconds: 1.0)
        let chunk1 = buffer.createNewChunkURL()
        XCTAssertTrue(chunk1.path.contains("AudioBufferChunkCache"))
        
        buffer.purgeAllBuffers()
    }
}
