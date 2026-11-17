import SwiftUI

struct SettingsView: View {
    @State private var keyInput = ""
    @State private var hasKey = AnthropicKey.load() != nil
    @State private var keyError: String?

    var body: some View {
        Form {
            Section("Ways to start listening") {
                tip("mic.fill", "Tap the big microphone.")
                tip("lock.fill", "Add the Time Tracker widget to your Lock Screen and tap it.")
                tip("switch.2", "Add the \u{201C}Log Time\u{201D} control to Control Center or the Lock Screen.")
                tip("hand.tap.fill", "Back Tap: make a \u{201C}Log Time\u{201D} shortcut with the \u{201C}Log by Voice\u{201D} action, then pick it in Settings \u{203A} Accessibility \u{203A} Touch \u{203A} Back Tap \u{203A} Double Tap.")
                tip("waveform", "Say \u{201C}Hey Siri, log time in Time Tracker\u{201D}.")
            }

            Section("Things you can say") {
                Text("\u{201C}Starting dishes\u{201D}")
                Text("\u{201C}Done with the dishes\u{201D}")
                Text("\u{201C}Finished laundry and starting dinner\u{201D}")
                Text("\u{201C}Stop\u{201D} \u{2013} stops the most recent one")
                Text("\u{201C}Stop everything\u{201D}")
                Text("Anything else is saved as a note.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if hasKey {
                    Label("Key saved on this iPhone", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button("Remove key", role: .destructive) {
                        AnthropicKey.remove()
                        hasKey = false
                    }
                } else {
                    SecureField("Anthropic API key", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        do {
                            try AnthropicKey.save(keyInput)
                            keyInput = ""
                            keyError = nil
                            hasKey = AnthropicKey.load() != nil
                        } catch {
                            keyError = "Couldn't save the key. Please try again."
                        }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let keyError {
                        Text(keyError).foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Smart features (coming soon)")
            } footer: {
                Text("Optional. A future update will use Claude Haiku to understand tricky phrases, group activities into categories, and write daily and weekly summaries. The key is stored only in this iPhone\u{2019}s Keychain. Your voice recordings are never sent anywhere.")
            }

            Section("Storage") {
                switch SharedStore.loaded.location {
                case .appGroup:
                    Label("Saved on this iPhone", systemImage: "internaldrive")
                case .appSandbox:
                    Label("Saved on this iPhone, but widgets can\u{2019}t see it (App Group not set up)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                case .inMemory:
                    Label("Storage failed to open. Entries won\u{2019}t be kept after the app closes.", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "\u{2013}")
                Text("Speech is turned into text on this iPhone. Audio never leaves the phone.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
        }
    }
}
