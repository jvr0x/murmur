import SwiftUI

/// First-run / permissions screen that shows the three required grants and links out to
/// the relevant System Settings panes.
public struct OnboardingView: View {
    /// Whether microphone access is granted.
    @State private var microphone = false
    /// Whether Accessibility is granted.
    @State private var accessibility = false
    /// Whether Input Monitoring is granted.
    @State private var inputMonitoring = false

    /// Creates the view.
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Murmur needs three permissions")
                .font(.title2).bold()
            Text("Grant each, then hold Right Option and speak.")
                .font(.callout).foregroundStyle(.secondary)

            permissionRow(
                name: "Microphone",
                detail: "Record your voice",
                granted: microphone
            ) {
                Task { _ = await Permissions.requestMicrophone(); refresh() }
            }

            permissionRow(
                name: "Accessibility",
                detail: "Insert text into other apps",
                granted: accessibility
            ) {
                Permissions.promptAccessibility()
                Permissions.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }

            permissionRow(
                name: "Input Monitoring",
                detail: "Detect the hold-to-talk hotkey",
                granted: inputMonitoring
            ) {
                Permissions.requestInputMonitoring()
                Permissions.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            }

            Spacer()
            Button("Refresh status", action: refresh)
        }
        .padding(24)
        .frame(width: 440, height: 340)
        .onAppear(perform: refresh)
    }

    /// Builds one permission row with a status icon and a Grant button.
    private func permissionRow(
        name: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant", action: action) }
        }
    }

    /// Re-reads the current permission states.
    private func refresh() {
        microphone = Permissions.hasMicrophone
        accessibility = Permissions.hasAccessibility
        inputMonitoring = Permissions.hasInputMonitoring
    }
}
