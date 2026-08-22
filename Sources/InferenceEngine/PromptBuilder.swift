import Foundation

/// Constructs token-accurate prompts for on-device Llama-3.2 and Qwen LLMs.
/// Dynamically anchors the current date, weekday, and timezone to eliminate relative date hallucinations.
public struct PromptBuilder {
    
    /// Generates the full formatted prompt string including Llama-3 special control tokens and semantic instructions.
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
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' hh:mm a"
        dateFormatter.timeZone = timeZone
        dateFormatter.locale = Locale(identifier: "en_US")
        let formattedDate = dateFormatter.string(from: referenceDate)
        
        let tzIdentifier = timeZone.identifier
        
        var template = LLMConfigurationManager.shared.customSystemPrompt
        if template.contains("{CURRENT_DATE}") {
            template = template.replacingOccurrences(of: "{CURRENT_DATE}", with: formattedDate)
        }
        if template.contains("{TIMEZONE}") {
            template = template.replacingOccurrences(of: "{TIMEZONE}", with: tzIdentifier)
        }
        
        let prompt = """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        \(template)
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        Meeting Transcript:
        
        \(transcript)
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        """
        
        return prompt
    }
}
