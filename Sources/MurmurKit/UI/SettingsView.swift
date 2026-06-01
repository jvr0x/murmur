import SwiftUI

/// The settings form, bound directly to the shared ``SettingsStore``.
///
/// The body is split into per-section subviews. Beyond readability, small `@ViewBuilder`
/// members keep each expression simple enough for the Swift type-checker to resolve
/// quickly (large SwiftUI `Form` bodies are pathologically slow to type-check).
public struct SettingsView: View {
    /// The shared settings store injected via the environment.
    @EnvironmentObject private var settings: SettingsStore

    /// Creates the view.
    public init() {}

    public var body: some View {
        Form {
            sttSection
            cleanupSection
            hotkeySection
            serverSection
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    /// Speech-to-text backend, endpoint, model, and language.
    @ViewBuilder private var sttSection: some View {
        Section("Speech-to-Text") {
            Picker("Backend", selection: $settings.config.sttBackend) {
                Text("Local (whisper.cpp)").tag(STTBackendKind.whisperCpp)
                Text("OpenAI-compatible (remote)").tag(STTBackendKind.openAICompatible)
            }
            TextField("Base URL", text: $settings.config.sttBaseURL)
            TextField("Model", text: $settings.config.sttModel)
            TextField("Language (auto or code)", text: $settings.config.language)
        }
    }

    /// Optional LLM cleanup configuration.
    @ViewBuilder private var cleanupSection: some View {
        Section("LLM Cleanup") {
            Toggle("Enable cleanup pass", isOn: $settings.config.cleanupEnabled)
            TextField("LLM Base URL", text: $settings.config.llmBaseURL)
            TextField("Model", text: $settings.config.llmModel)
            TextField("Timeout (seconds)", value: $settings.config.cleanupTimeout, format: .number)
            cleanupPromptEditor
        }
    }

    /// The editable cleanup prompt.
    @ViewBuilder private var cleanupPromptEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cleanup prompt").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $settings.config.cleanupPrompt)
                .font(.body.monospaced())
                .frame(height: 120)
                .border(Color.secondary.opacity(0.3))
        }
    }

    /// Hotkey and text-insertion configuration.
    @ViewBuilder private var hotkeySection: some View {
        Section("Hotkey & Insertion") {
            TextField("Hotkey key code (61 = Right Option)", value: hotkeyBinding, format: .number)
            Picker("Insertion method", selection: $settings.config.insertionMethod) {
                Text("Paste (Cmd-V)").tag(InsertionMethod.paste)
                Text("Keystroke").tag(InsertionMethod.keystroke)
            }
            Toggle("Restore clipboard after paste", isOn: $settings.config.restoreClipboard)
        }
    }

    /// Local server configuration.
    @ViewBuilder private var serverSection: some View {
        Section("Local Server") {
            TextField("whisper.cpp port", value: portBinding, format: .number)
            Text("Changing the port takes effect on next launch.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A binding to the hotkey key code as an `Int` (the field formats integers).
    private var hotkeyBinding: Binding<Int> {
        Binding(
            get: { Int(settings.config.hotkeyKeyCode) },
            set: { settings.config.hotkeyKeyCode = UInt16(max(0, $0)) }
        )
    }

    /// A binding to the whisper server port as an `Int`.
    private var portBinding: Binding<Int> {
        Binding(
            get: { settings.config.whisperServerPort },
            set: { settings.config.whisperServerPort = $0 }
        )
    }
}
