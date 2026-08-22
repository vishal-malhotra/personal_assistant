import Foundation
import Combine

/// Manages persistent on-device LLM hyperparameters, system prompt customization, and inference optimization.
public final class LLMConfigurationManager: ObservableObject {
    public static let shared = LLMConfigurationManager()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let kCustomSystemPrompt = "cfg_custom_system_prompt"
    private let kTemperature = "cfg_temperature"
    private let kTopP = "cfg_top_p"
    private let kMaxTokens = "cfg_max_tokens"
    private let kWhisperEnabled = "cfg_whisper_enabled"
    private let kSelectedLanguage = "cfg_selected_language"
    
    public static let defaultSystemPrompt = """
You are an advanced on-device AI meeting intelligence assistant with deep semantic understanding of English, Hinglish, and Hindi.

Your objective is to thoroughly comprehend the meeting transcript and produce a strictly valid JSON object.

Guidelines for Reasoning:
1. Context & Synthesis: Understand implicit agreements, debates, and speaker consensus across the entire conversation.
2. Executive Summary: Write a clear synthesis covering the primary focus, key points discussed, and outcomes.
3. Key Decisions: Extract concrete conclusions reached by the participants.
4. Dialogue Turns: Attribute turns to Speaker 1 and Speaker 2 (or real names if mentioned in speech).
5. Temporal Grounding: Anchor relative references (e.g., 'tomorrow', 'next Tuesday', 'kal shaam 5 baje', 'after lunch', 'subah 10 baje') relative to Current Date: {CURRENT_DATE} (Timezone: {TIMEZONE}).
6. Events vs Reminders:
   - Calendar Events: Discussions, syncs, reviews, client calls that involve scheduled meeting times.
   - Reminders: Concrete tasks, follow-ups, deliverables, slide preparations, or document submissions.
   - If no scheduling is mentioned, return empty arrays [].

Output ONLY the raw JSON adhering to this exact schema:
{
  "meeting_summary": "Executive summary of the discussion.",
  "key_decisions": ["Decision 1", "Decision 2"],
  "action_items": ["Action item 1", "Action item 2"],
  "dialogue_turns": [
    { "speaker": "Speaker 1", "text": "Sentence spoken" }
  ],
  "calendar_events": [
    {
      "title": "Descriptive Event Title",
      "date": "YYYY-MM-DD",
      "time": "HH:MM AM/PM",
      "attendees": ["Name 1", "Name 2"]
    }
  ],
  "reminders": [
    {
      "title": "Descriptive Task Title",
      "due_date": "YYYY-MM-DD",
      "time": "HH:MM AM/PM"
    }
  ]
}
"""
    
    @Published public var customSystemPrompt: String {
        didSet { defaults.set(customSystemPrompt, forKey: kCustomSystemPrompt) }
    }
    
    @Published public var temperature: Double {
        didSet { defaults.set(temperature, forKey: kTemperature) }
    }
    
    @Published public var topP: Double {
        didSet { defaults.set(topP, forKey: kTopP) }
    }
    
    @Published public var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: kMaxTokens) }
    }
    
    @Published public var isWhisperRefinementEnabled: Bool {
        didSet { defaults.set(isWhisperRefinementEnabled, forKey: kWhisperEnabled) }
    }
    
    private init() {
        self.customSystemPrompt = defaults.string(forKey: kCustomSystemPrompt) ?? Self.defaultSystemPrompt
        self.temperature = defaults.object(forKey: kTemperature) != nil ? defaults.double(forKey: kTemperature) : 0.2
        self.topP = defaults.object(forKey: kTopP) != nil ? defaults.double(forKey: kTopP) : 0.9
        self.maxTokens = defaults.object(forKey: kMaxTokens) != nil ? defaults.integer(forKey: kMaxTokens) : 1024
        self.isWhisperRefinementEnabled = defaults.object(forKey: kWhisperEnabled) != nil ? defaults.bool(forKey: kWhisperEnabled) : true
    }
    
    public func resetPromptToDefault() {
        self.customSystemPrompt = Self.defaultSystemPrompt
    }
    
    public func resetAllToDefaults() {
        self.customSystemPrompt = Self.defaultSystemPrompt
        self.temperature = 0.2
        self.topP = 0.9
        self.maxTokens = 1024
        self.isWhisperRefinementEnabled = true
    }
}
