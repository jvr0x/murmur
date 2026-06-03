import SwiftUI

/// First-run / permissions screen showing the three required grants. Status updates **live**
/// as the user grants each one (no manual refresh needed) via the shared `PermissionsModel`,
/// and the rows link out to the relevant System Settings panes.
public struct OnboardingView: View {
    /// Live permission state, shared with the app so grants take effect immediately.
    @ObservedObject private var model: PermissionsModel

    /// Creates the view bound to the shared permissions model.
    /// - Parameter model: The live permission state.
    public init(model: PermissionsModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Murmur needs three permissions")
                .font(.title2).bold()
            Text("Grant each, then hold your hotkey and speak.")
                .font(.callout).foregroundStyle(.secondary)

            permissionRow(
                name: "Microphone",
                detail: "Record your voice",
                granted: model.snapshot.microphone
            ) {
                Task { _ = await Permissions.requestMicrophone(); model.refresh() }
            }

            permissionRow(
                name: "Accessibility",
                detail: "Insert text into other apps",
                granted: model.snapshot.accessibility
            ) {
                Permissions.promptAccessibility()
                Permissions.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }

            permissionRow(
                name: "Input Monitoring",
                detail: "Detect the hold-to-talk hotkey",
                granted: model.snapshot.inputMonitoring
            ) {
                Permissions.requestInputMonitoring()
                Permissions.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            }

            Spacer()
            HStack {
                if model.snapshot.allGranted {
                    Label("All set — hold your hotkey and speak", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                Spacer()
                Button("Refresh status") { model.refresh() }
            }
        }
        .padding(24)
        .frame(width: 440, height: 340)
        .onAppear {
            model.start()
            model.refresh()
        }
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
}
