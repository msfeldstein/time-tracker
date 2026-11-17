import SwiftUI

struct MicButton: View {
    let phase: VoiceCaptureController.Phase
    let action: () -> Void

    @State private var pulse = false

    private var isListening: Bool { phase == .listening }
    private var isWorking: Bool { phase == .preparing || phase == .saving }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.35), lineWidth: 10)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .opacity(isListening ? (pulse ? 0 : 1) : 0)

                Circle()
                    .fill(isListening ? Color.red : Color.accentColor)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)

                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    Image(systemName: isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 180, height: 180)
        }
        .buttonStyle(.plain)
        .disabled(phase == .saving)
        .accessibilityLabel(isListening ? "Stop listening" : "Start listening")
        .accessibilityHint("Say something like starting dishes, or done with dishes")
        .onChange(of: isListening, initial: true) { _, listening in
            if listening {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            } else {
                withAnimation(.default) { pulse = false }
            }
        }
    }
}
