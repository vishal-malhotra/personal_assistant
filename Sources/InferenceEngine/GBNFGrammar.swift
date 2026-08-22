import Foundation

/// Grammar-Based Network Format (GBNF) definitions.
/// Used by llama.cpp and quantized inference samplers to constrain token selection,
/// guaranteeing 100% syntactically valid JSON matching `MeetingPayload`.
public enum GBNFGrammar {
    
    /// Strict GBNF grammar specification for `MeetingPayload` JSON schema.
    public static let meetingExtractionGrammar: String = """
    root ::= "{" ws "\\"meeting_summary\\"" ws ":" ws string "," ws "\\"key_decisions\\"" ws ":" ws stringlist "," ws "\\"action_items\\"" ws ":" ws stringlist "," ws "\\"dialogue_turns\\"" ws ":" ws turnlist "," ws "\\"calendar_events\\"" ws ":" ws eventlist "," ws "\\"reminders\\"" ws ":" ws reminderlist ws "}"
    
    turnlist ::= "[" ws (turn ("," ws turn)*)? ws "]"
    turn ::= "{" ws "\\"speaker\\"" ws ":" ws string "," ws "\\"text\\"" ws ":" ws string ws "}"
    
    eventlist ::= "[" ws (event ("," ws event)*)? ws "]"
    event ::= "{" ws "\\"title\\"" ws ":" ws string "," ws "\\"date\\"" ws ":" ws datestring "," ws "\\"time\\"" ws ":" ws timestring "," ws "\\"attendees\\"" ws ":" ws stringlist ws "}"
    
    reminderlist ::= "[" ws (reminder ("," ws reminder)*)? ws "]"
    reminder ::= "{" ws "\\"title\\"" ws ":" ws string "," ws "\\"due_date\\"" ws ":" ws datestring "," ws "\\"time\\"" ws ":" ws timestring ws "}"
    
    stringlist ::= "[" ws (string ("," ws string)*)? ws "]"
    
    datestring ::= "\\"" [0-9] [0-9] [0-9] [0-9] "-" [0-9] [0-9] "-" [0-9] [0-9] "\\""
    timestring ::= "\\"" [0-9] [0-9] ":" [0-9] [0-9] " " ("AM" | "PM") "\\""
    
    string ::= "\\"" ([^"\\\\\\x00-\\x1F] | "\\\\" (["\\\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]))* "\\""
    ws ::= [ \\t\\n\\r]*
    """
}
