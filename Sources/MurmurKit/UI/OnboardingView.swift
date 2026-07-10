import SwiftUI

/// First-run / permissions screen showing the three required grants. Status updates **live**
/// as the user grants each one (no manual refresh needed) via the shared `PermissionsModel`.
///
/// Nothing prompts the system on its own: each macOS confirmation appears only when the user
/// clicks that row's **Grant**. A secondary **Open Settings** link is offered too, because the
/// Accessibility and Input Monitoring system dialogs appear only the *first* time — once
/// dismissed or denied, macOS never re-shows them, so the privacy pane is the only path back.
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
            Text("Click Grant on each row — that's what shows the macOS confirmation. Nothing pops up until you do.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                name: "Microphone",
                detail: "Record your voice",
                granted: model.snapshot.microphone,
                pane: Permissions.microphonePane,
                grant: {
                    // Prompt only while undetermined; otherwise macOS won't ask again, so the
                    // pane is the only path. The decision is a pure, tested helper.
                    switch Permissions.microphoneGrantAction(for: Permissions.microphoneStatus) {
                    case .requestSystemPrompt:
                        Task { _ = await Permissions.requestMicrophone(); model.refresh() }
                    case .openSystemSettings:
                        Permissions.openSettings(Permissions.microphonePane)
                    }
                }
            )

            permissionRow(
                name: "Accessibility",
                detail: "Insert text into other apps",
                granted: model.snapshot.accessibility,
                pane: Permissions.accessibilityPane,
                // Reason: the Accessibility system dialog carries its own "Open System
                // Settings" button, so prompt only — also opening the pane is the old double pop.
                grant: { Permissions.promptAccessibility() }
            )

            permissionRow(
                name: "Input Monitoring",
                detail: "Detect the hold-to-talk hotkey",
                granted: model.snapshot.inputMonitoring,
                pane: Permissions.inputMonitoringPane,
                grant: { Permissions.requestInputMonitoring() }
            )

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
        .frame(width: 440, height: 380)
        .onAppear {
            model.start()
            model.refresh()
        }
    }

    /// Builds one permission row: a status icon, the name/detail, and — while not yet granted —
    /// a secondary borderless "Open Settings" link plus the primary "Grant" button.
    /// - Parameters:
    ///   - name: The human-readable permission name.
    ///   - detail: A one-line explanation of why Murmur needs it.
    ///   - granted: Whether the permission is currently granted.
    ///   - pane: The System Settings privacy-pane URL the secondary button opens.
    ///   - grant: The primary action run when "Grant" is clicked.
    private func permissionRow(
        name: String,
        detail: String,
        granted: Bool,
        pane: String,
        grant: @escaping () -> Void
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
            if !granted {
                Button("Open Settings") { Permissions.openSettings(pane) }
                    .buttonStyle(.link)
                Button("Grant", action: grant)
            }
        }
    }
}
