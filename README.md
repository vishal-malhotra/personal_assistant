# iOS Offline AI Personal Assistant (100% On-Device)

A private, fully offline, on-device AI personal assistant built for iOS with Swift 6 and SwiftUI.

It records meetings, transcribes audio using Apple Neural Engine-accelerated Speech-to-Text (`SFSpeechRecognizer`), summarizes discussions with a 4-bit quantized local LLM (Llama-3.2-3B-Instruct), and automatically schedules calendar events and reminders via `EventKit` upon user confirmation.

---

## Architecture Overview

```
[ Start Meeting ] ──> [ AVAudioEngine + Accelerate VAD ] ──> [ SFSpeechRecognizer (45s Cycles) ]
                                                                             │
[ End Meeting ] <────────────────────────────────────────────────────────────┘
       │
       ▼
[ Release Audio Buffers ] ──> [ Load Quantized LLM (Foreground) ] ──> [ GBNF Grammar Decoding ]
                                                                             │
[ EventKit Confirmation Sheet ] <── [ Purge LLM Memory ] <──────────────────┘
```

### Key Technical Pillars
1. **Decoupled Sequential Lifecycle:** Keeps memory under Jetsam limits by running ASR during background recording, then tearing down audio buffers before loading the LLM in foreground.
2. **Apple Silicon Acceleration:** `SFSpeechRecognizer` runs out-of-process with zero RAM footprint; LLM uses Metal GPU acceleration.
3. **Continuous Recognition Resilience:** Automates 45-second rolling cycles to overcome Apple's native 60-second recognition timeout.
4. **Voice Activity Detection (VAD):** Employs Accelerate vDSP to filter dead air and save up to 70% battery and compute.
5. **Guaranteed Schema (GBNF Grammar):** Strictly constrains token generation to eliminate markdown hallucinations and invalid JSON formats.
6. **Privacy & Security:** Encrypted at rest via `NSFileProtectionComplete`. Zero cloud egress, zero analytics.

---

## Required Xcode Entitlements & Info.plist Keys

Add the following keys to your application target's `Info.plist`:

```xml
<!-- Background Audio Mode -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>

<!-- Privacy Permissions -->
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone to transcribe meeting discussions on-device.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>We use on-device speech recognition to convert your voice to text completely offline.</string>

<key>NSCalendarsFullAccessUsageDescription</key>
<string>We use your calendar to schedule meetings extracted from your notes with your approval.</string>

<key>NSRemindersFullAccessUsageDescription</key>
<string>We use Reminders to save action items extracted from your notes with your approval.</string>
```

For devices with 8GB RAM (iPhone 15 Pro / iPhone 16), add to your `.entitlements`:
```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

---

## Project Structure

```
Sources/
├── AudioPipeline/
│   ├── AudioSessionManager.swift       // AVAudioSession lifecycle & route handling
│   ├── VADFilter.swift                 // Accelerate vDSP Voice Activity Detection
│   ├── RollingAudioBuffer.swift        // Ephemeral 30s chunk cache with auto-shredding
│   └── SpeechRecognitionService.swift  // 45s rolling on-device speech recognizer
├── InferenceEngine/
│   ├── JSONSchemaModels.swift          // Strongly typed Codable payloads for EventKit
│   ├── GBNFGrammar.swift               // GBNF grammar specification for token samplers
│   ├── PromptBuilder.swift             // Dynamic Llama-3 prompt builder with date/tz anchoring
│   └── ModelManager.swift              // Memory-safe Actor with deinit memory purging
├── ActionExecution/
│   ├── EventKitService.swift           // Calendar and Reminders integration with conflict check
│   └── ActionConfirmationManager.swift // Approval pipeline for scheduling & tasks
├── Storage/
│   └── TranscriptStore.swift           // NSFileProtectionComplete encrypted meeting history
├── LiveActivity/
│   └── MeetingActivityAttributes.swift // ActivityKit Dynamic Island & Lock Screen state
├── UI/
│   ├── Theme.swift                     // Dark mode tokens, neon gradients & Siri aesthetic
│   ├── MainDashboardView.swift         // Primary hub with history list & floating action button
│   ├── ActiveRecordingView.swift       // Live waveform visualizer & streaming transcript
│   ├── ProcessingOverlayView.swift     // Animated Siri orb loading state
│   └── ActionReviewSheetView.swift     // Interactive EventKit approval sheet
└── PersonalAssistantApp.swift          // App entry point
```

---

## Development & Testing

Open `Package.swift` in Xcode 15+ or build with Swift PM:
```bash
swift test
```
