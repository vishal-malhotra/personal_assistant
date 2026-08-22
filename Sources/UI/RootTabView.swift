import SwiftUI

public struct RootTabView: View {
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            MainDashboardView()
                .tabItem {
                    Label("Meetings", systemImage: "waveform.badge.mic")
                }
                .tag(0)
            
            AssistantChatView()
                .tabItem {
                    Label("Ask AI", systemImage: "bubble.left.and.sparkles.fill")
                }
                .tag(1)
            
            SettingsConfigView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(AssistantTheme.systemBlue)
    }
}
