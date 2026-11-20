import SwiftUI
import TimeTrackerCore

struct SettingsView: View {
    @State private var keyInput = ""
    @State private var keySource = AnthropicKey.source
    @State private var keyError: String?
    @State private var aiEnabled = AISettings.isEnabled
    @State private var testing = false
    @State private var testResult: (ok: Bool, message: String)?

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
                Toggle("Use AI (Claude Haiku)", isOn: $aiEnabled)
                    .onChange(of: aiEnabled) { _, isOn in
                        AISettings.isEnabled = isOn
                        AIWorker.shared.settingsChanged()
                    }
                Text(AISettings.disclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                switch keySource {
                case .settings:
                    Label("Using the key you entered", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                case .builtIn:
                    Label("Using the key built into this app", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                case .missing:
                    EmptyView()
                }

                if keySource != .missing {
                    Button {
                        testKey()
                    } label: {
                        if testing {
                            HStack { ProgressView(); Text("Testing\u{2026}") }
                        } else {
                            Text("Test key")
                        }
                    }
                    .disabled(testing)
                    if let testResult {
                        Label(testResult.message, systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testResult.ok ? .green : .red)
                    }
                }

                if keySource == .settings {
                    Button(AnthropicKey.bundledKey() == nil ? "Remove key" : "Remove key and use the built-in one", role: .destructive) {
                        AnthropicKey.remove()
                        keySource = AnthropicKey.source
                        testResult = nil
                        AIWorker.shared.settingsChanged()
                    }
                } else {
                    SecureField(keySource == .builtIn ? "Use a different key (optional)" : "Anthropic API key", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !keyInput.trimmingCharacters(in: .whitespaces).isEmpty || keySource == .missing {
                        Button("Save key") {
                            do {
                                try AnthropicKey.save(keyInput)
                                keyInput = ""
                                keyError = nil
                                keySource = AnthropicKey.source
                                AIWorker.shared.settingsChanged()
                                testKey()
                            } catch {
                                keyError = "Couldn\u{2019}t save the key. Please try again."
                            }
                        }
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let keyError {
                        Text(keyError).foregroundStyle(.red)
                    }
                }

                if aiEnabled && keySource != .missing {
                    LabeledContent("Status", value: AIWorker.shared.status.description)
                }
            } header: {
                Text("Smart features")
            } footer: {
                Text("Optional. Claude Haiku sorts activities into categories, makes sense of unclear voice notes, suggests when a forgotten timer probably ended, and writes your summaries. Everything still works offline or without a key; AI work waits and retries later. A key you enter is stored only in this iPhone\u{2019}s Keychain and takes priority over a built-in one.")
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

    private func testKey() {
        testing = true
        testResult = nil
        Task {
            do {
                try await LLMServices.claude().testConnection()
                testResult = (true, "The key works.")
            } catch let error as LLMServiceError {
                testResult = (false, error.userMessage)
            } catch {
                testResult = (false, error.localizedDescription)
            }
            testing = false
        }
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
