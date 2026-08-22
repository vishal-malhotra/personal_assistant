import Foundation

/// Constructs token-accurate prompts for on-device Llama-3.2-3B-Instruct.
/// Dynamically anchors the current date, weekday, and timezone to eliminate relative date hallucinations.
public struct PromptBuilder {
    
    /// Generates the full formatted prompt string including Llama-3 special control tokens.
    /// - Parameters:
    ///   - transcript: The transcribed text from the meeting.
    ///   - referenceDate: Reference date for relative date computation (defaults to `Date()`).
    ///   - timeZone: User's local timezone (defaults to `.current`).
    /// - Returns: Token-ready prompt string.
    public static func buildPrompt(
        transcript: String,
        referenceDate: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        dateFormatter.timeZone = timeZone
        dateFormatter.locale = Locale(identifier: "en_US")
        let formattedDate = dateFormatter.string(from: referenceDate)
        
        let tzIdentifier = timeZone.identifier
        
        let systemContent = """
        You are an ultra-efficient on-device AI assistant. Your ONLY job is to read raw meeting transcripts and output a strict, parseable JSON object.
        
        Do not include greetings, explanations, markdown code fences (like ```json), or any conversational text. Output ONLY the raw JSON object.
        
        Your JSON must strictly adhere to the following schema:
        {
          "meeting_summary": "A concise 2-3 sentence summary of the discussion.",
          "action_items": ["Action item 1", "Action item 2"],
          "calendar_events": [
            {
              "title": "Event Name",
              "date": "YYYY-MM-DD",
              "time": "HH:MM AM/PM",
              "attendees": ["Name 1", "Name 2"]
            }
          ],
          "reminders": [
            {
              "title": "Reminder task",
              "due_date": "YYYY-MM-DD",
              "time": "HH:MM AM/PM"
            }
          ]
        }
        
        If no events or reminders are found, return empty arrays []. Use the context clues to identify speakers if speaker tags are missing.
        Today's date is \(formattedDate) (Timezone: \(tzIdentifier)).
        """
        
        let prompt = """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        \(systemContent)
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        Transcript:
        
        \(transcript)
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        """
        
        return prompt
    }
}
