import SwiftUI
import ServiceManagement

/// The preferences window for n-doc monitor.
///
/// **Step 8 — App lifecycle:**
///
/// This view is shown in the standard macOS Settings window (⌘,).
/// It provides app configuration options like launch-at-login.
///
/// **SwiftUI concept — `Settings` scene:**
/// SwiftUI apps can declare a `Settings { }` scene that
/// automatically creates a Preferences window accessible via
/// the app menu or ⌘,.  The view inside is a normal SwiftUI view.
///
/// **SwiftUI concept — `@AppStorage`:**
/// A property wrapper that reads/writes a value from `UserDefaults`.
/// When the value changes, SwiftUI automatically re-renders views
/// that depend on it.  This is the simplest way to persist user
/// preferences.
struct SettingsView: View {

    /// Whether the app should launch at login.
    ///
    /// Stored in `UserDefaults` via `@AppStorage`.  The actual
    /// registration with the system is done via `SMAppService`.
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Label("General", systemImage: "gear")
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 120)
        .onAppear {
            syncLaunchAtLoginState()
        }
    }

    // MARK: - Launch at login

    /// Register or unregister the app as a login item.
    ///
    /// **AppKit concept — `SMAppService`:**
    /// `SMAppService.mainApp` represents the current app's login
    /// item registration.  `.register()` adds it to the user's
    /// login items; `.unregister()` removes it.
    ///
    /// This only works when the app is running as a proper `.app`
    /// bundle.  When running from Xcode or `swift run`, the call
    /// may fail silently — that's fine for development.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Fails when not running as a .app bundle (e.g. swift run).
            // Silently ignore — the toggle still reflects the user's intent.
            print("SMAppService error: \(error.localizedDescription)")
        }
    }

    /// Sync the toggle state with the actual system registration.
    private func syncLaunchAtLoginState() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }
}
