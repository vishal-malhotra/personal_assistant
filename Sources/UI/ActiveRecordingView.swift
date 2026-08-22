import SwiftUI

public struct ActiveRecordingView: View {
    @ObservedObject var speechService = SpeechRecognitionService.shared
    let onStop: () -> Void
    
    public init(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Header: Stopwatch Timer (Apple Voice Memos Style)
                VStack(spacing: 8) {
                    Text(formattedDigitalTimer(speechService.sessionDuration))
                        .font(.system(size: 44, weight: .light, design: .monospaced))
                        .foregroundColor(AssistantTheme.systemRed)
                    
                    Text("Recording Meeting...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Clean Monochromatic Waveform Visualizer
                HStack(spacing: 3) {
                    ForEach(0..<32, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.75))
                            .frame(
                                width: 3,
                                height: max(4, CGFloat(speechService.audioLevel) * 80 * waveformCurve(for: index))
                            )
                            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: speechService.audioLevel)
                    }
                }
                .frame(height: 90)
                
                Spacer()
                
                // Real-time Text Preview (Clean Subtle Card)
                VStack(alignment: .leading, spacing: 6) {
                    Text("LIVE TRANSCRIPT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(0.5)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(speechService.liveTranscript.isEmpty ? "Listening for speech..." : speechService.liveTranscript)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(speechService.liveTranscript.isEmpty ? .white.opacity(0.3) : .white.opacity(0.9))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("LiveBottom")
                        }
                        .frame(height: 120)
                        .onChange(of: speechService.liveTranscript) {
                            withAnimation {
                                proxy.scrollTo("LiveBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Bottom Controls: Apple Voice Memos Style Record / Stop Button
                VStack(spacing: 12) {
                    Button(action: onStop) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 72, height: 72)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AssistantTheme.systemRed)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .accessibilityLabel("Stop Recording")
                    
                    Text("Done")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    private func formattedDigitalTimer(_ seconds: TimeInterval) -> String {
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hrs > 0 {
            return String(format: "%02d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
    
    private func waveformCurve(for index: Int) -> CGFloat {
        let normalized = sin(Double(index) / 32.0 * .pi)
        return CGFloat(normalized * 1.1 + 0.2)
    }
}
