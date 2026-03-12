import SwiftUI

/// Settings window for configuring language, whisper model, and Ollama model.
struct PreferencesView: View {
    @ObservedObject var orchestrator: PipelineOrchestrator

    @AppStorage("preferredLanguage") private var languageSetting = "de"
    @AppStorage("whisperModel") private var whisperModelSetting = WhisperModel.default.rawValue
    @AppStorage("ollamaModel") private var ollamaModel = OllamaFormatter.defaultModel
    @AppStorage("hotkeyChoice") private var hotkeyChoice = HotkeyChoice.default.rawValue
    @AppStorage("outputMode") private var outputModeSetting = OutputMode.clipboard.rawValue
    @AppStorage("formatGeneral") private var formatGeneral = true
    @AppStorage("formatEmail") private var formatEmail = true

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Language", selection: $languageSetting) {
                    Text("German").tag("de")
                    Text("English").tag("en")
                    Text("Auto-detect").tag("auto")
                }
                .onChange(of: languageSetting) { _, newValue in
                    orchestrator.preferredLanguage = Language(rawValue: newValue)
                }

                Picker("Whisper Model", selection: $whisperModelSetting) {
                    ForEach(WhisperModel.allCases) { model in
                        HStack {
                            Text(model.displayName)
                            Text(model.sizeDescription)
                                .foregroundStyle(.secondary)
                            if model == .default {
                                Text("Recommended")
                                    .font(.caption)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        .tag(model.rawValue)
                    }
                }
                .disabled(orchestrator.modelLoading)
                .onChange(of: whisperModelSetting) { _, newValue in
                    guard let model = WhisperModel(rawValue: newValue) else { return }
                    Task {
                        await orchestrator.switchWhisperModel(model)
                    }
                }

                if orchestrator.modelLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading model…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Hotkey") {
                Picker("Push-to-talk key", selection: $hotkeyChoice) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }

                if hotkeyChoice == HotkeyChoice.fn.rawValue {
                    Text("Set \"Press fn key to\" → \"Do Nothing\" in System Settings → Keyboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Output") {
                Picker("After transcription", selection: $outputModeSetting) {
                    Text("Copy to clipboard").tag(OutputMode.clipboard.rawValue)
                    Text("Paste directly").tag(OutputMode.paste.rawValue)
                }
                .onChange(of: outputModeSetting) { _, newValue in
                    orchestrator.outputMode = OutputMode(rawValue: newValue) ?? .clipboard
                }

                if outputModeSetting == OutputMode.paste.rawValue {
                    Text("Requires Accessibility permission. Text is also saved to clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Formatting") {
                Toggle("Format general transcriptions", isOn: $formatGeneral)
                Toggle("Format email transcriptions", isOn: $formatEmail)

                if !formatGeneral && !formatEmail {
                    Text("All formatting disabled — raw transcription will be used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if orchestrator.availableModels.isEmpty {
                    TextField("Ollama model", text: $ollamaModel)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Ollama model", selection: $ollamaModel) {
                        ForEach(orchestrator.availableModels, id: \.self) { model in
                            HStack {
                                Text(model)
                                if let desc = modelDescription(model) {
                                    Text(desc)
                                        .foregroundStyle(.secondary)
                                }
                                if model == OllamaFormatter.defaultModel {
                                    Text("Recommended")
                                        .font(.caption)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.blue.opacity(0.15))
                                        .foregroundStyle(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .tag(model)
                        }
                    }
                }

                Text("Showing models installed on your machine. For best results, use qwen3.5. Install more with `ollama pull <model>` in Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Circle()
                        .fill(orchestrator.ollamaAvailable ? .green : .yellow)
                        .frame(width: 8, height: 8)
                    Text(orchestrator.ollamaAvailable ? "Ollama connected" : "Ollama unavailable — raw transcription will be used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 540)
        .task {
            await orchestrator.refreshAvailableModels()
        }
    }

    private func modelDescription(_ name: String) -> String? {
        switch name {
        case let n where n.contains("0.8b"): return "Fastest, basic quality"
        case let n where n.contains(":2b"):  return "Fast, good quality"
        case let n where n.contains(":4b"):  return "Balanced, best for most users"
        case let n where n.contains(":9b"):  return "Slowest, highest quality"
        default: return nil
        }
    }
}