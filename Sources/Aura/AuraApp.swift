import AppKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var updateManager = UpdateManager()

    init() {
        let launchInDemoMode = CommandLine.arguments.contains("--demo")
        do {
            let store = try PersistenceStore()
            _model = State(initialValue: AppModel(store: store, launchInDemoMode: launchInDemoMode))
        } catch {
            do {
                let store = try PersistenceStore(inMemory: true)
                let fallback = AppModel(store: store, launchInDemoMode: launchInDemoMode)
                fallback.usingTemporaryStore = true
                fallback.persistenceIssue =
                    "Aura could not open its local database. It is running with temporary data so the original store remains untouched. \(Redactor.redact(error.localizedDescription))"
                _model = State(initialValue: fallback)
            } catch {
                fatalError("Aura could not create a recovery data store: \(Redactor.redact(error.localizedDescription))")
            }
        }
    }

    var body: some Scene {
        WindowGroup("Aura", id: "dashboard") {
            ThemedSceneRoot(preferences: model.preferences) {
                DashboardView()
                    .environment(model)
                    .environment(updateManager)
                    .modifier(AuraDeepLinkHandler(model: model))
            }
        }
        .defaultSize(width: 1100, height: 760)
        .handlesExternalEvents(matching: [AuraDeepLink.scheme])
        .modelContainer(model.store.container)

        MenuBarExtra {
            ThemedSceneRoot(preferences: model.preferences) {
                MenuBarControlCenterView()
                    .environment(model)
                    .modelContainer(model.store.container)
            }
        } label: {
            MenuBarBrandMark()
                .frame(width: 18, height: 18)
                .accessibilityLabel(model.isPrivate ? "Aura, private" : "Aura")
        }
        .menuBarExtraStyle(.window)

        Settings {
            ThemedSceneRoot(preferences: model.preferences) {
                SettingsWindowView()
                    .environment(model)
                    .environment(updateManager)
                    .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 640)
            }
        }
        .modelContainer(model.store.container)

        .commands {
            AuraCommands(model: model)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updateManager.checkForUpdates() }
            }
        }
    }
}

private struct AuraCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Quick Open…") {
                model.commandPalettePresented = true
                NSApp.showDashboard(using: openWindow)
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            ForEach(Array(DashboardSection.allCases.enumerated()), id: \.element.id) { index, section in
                Button(section.title) {
                    model.navigate(to: section)
                    NSApp.showDashboard(using: openWindow)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }

            Divider()

            if model.isPrivate {
                Button("End Private Mode") { model.endPrivateMode() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            } else {
                Button("Go Private Until Resumed") { model.setPrivate(until: nil) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

extension NSApplication {
    func showDashboard(using openWindow: OpenWindowAction) {
        if let dashboard = windows.first(where: { $0.identifier?.rawValue.contains("dashboard") == true }) {
            dashboard.makeKeyAndOrderFront(nil)
            dashboard.orderFrontRegardless()
        } else {
            openWindow(id: "dashboard")
        }
        activate(ignoringOtherApps: true)
    }
}

/// Deep links into the Mac app, such as `aura://now-playing` from the widget.
enum AuraDeepLink: Equatable {
    static let scheme = "aura"

    case nowPlaying

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // Accept both `aura://now-playing` (host) and `aura:now-playing` (path).
        let target = (url.host() ?? url.path()).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch target {
        case "now-playing": self = .nowPlaying
        default: return nil
        }
    }
}

private struct AuraDeepLinkHandler: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    func body(content: Content) -> some View {
        content
            // Reuse the existing dashboard window instead of opening a new one per link.
            .handlesExternalEvents(preferring: [AuraDeepLink.scheme], allowing: ["*"])
            .onOpenURL { url in
                guard let link = AuraDeepLink(url: url) else { return }
                switch link {
                case .nowPlaying:
                    model.commandPalettePresented = false
                    model.navigate(to: .nowPlaying)
                }
                NSApp.showDashboard(using: openWindow)
            }
    }
}

private struct ThemedSceneRoot<Content: View>: View {
    let preferences: Preferences
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        let resolvedScheme = preferences.appearanceMode.preferredColorScheme ?? systemColorScheme
        let theme = preferences.theme(for: resolvedScheme)
        content
            .environment(\.appTheme, theme)
            .preferredColorScheme(preferences.appearanceMode.preferredColorScheme)
            .tint(theme.primaryColor)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let section = response.notification.request.content.userInfo["section"] as? String
        await MainActor.run {
            NotificationCenter.default.post(
                name: .auraOpenSection,
                object: nil,
                userInfo: section.map { ["section": $0] }
            )
        }
    }
}
