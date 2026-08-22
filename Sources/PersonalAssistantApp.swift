import SwiftUI

@main
public struct PersonalAssistantApp: App {
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
    }
}
