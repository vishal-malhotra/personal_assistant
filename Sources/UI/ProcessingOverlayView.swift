import SwiftUI

public struct ProcessingOverlayView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.4)
                
                Text("Processing Audio...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                
                Text("Extracting notes and action items on-device")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(24)
            .background(Color(uiColor: .systemGray6).opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
        }
    }
}
