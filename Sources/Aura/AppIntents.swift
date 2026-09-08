import AppIntents
import Foundation

enum PrivateModeIntentAction: String, AppEnum {
    case start
    case end

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Private Mode Action")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .start: "Start Private Mode",
        .end: "End Private Mode",
    ]

    @MainActor
    func apply(to preferences: Preferences) {
        switch self {
        case .start:
            preferences.privateMode = true
            preferences.privateUntil = nil
        case .end:
            preferences.privateMode = false
            preferences.privateUntil = nil
        }
    }
}

struct SetAuraPrivateModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Aura Private Mode"
    static let description = IntentDescription("Starts or ends Aura Private Mode without sharing listening metadata.")

    @Parameter(title: "Action") var action: PrivateModeIntentAction

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$action) in Aura")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            action.apply(to: Preferences.shared)
            NotificationCenter.default.post(
                name: .auraPrivateModeIntent,
                object: nil,
                userInfo: ["action": action.rawValue]
            )
        }
        let message = action == .start ? "Aura is private." : "Aura sharing can resume."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct GetAuraPrivacyStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Aura Privacy Status"
    static let description = IntentDescription("Reports whether Aura Private Mode is active.")

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let isPrivate = await MainActor.run {
            let preferences = Preferences.shared
            return preferences.privateMode
                && (preferences.privateUntil == nil || preferences.privateUntil! > .now)
        }
        let message = isPrivate ? "Aura Private Mode is on." : "Aura Private Mode is off."
        return .result(value: isPrivate, dialog: IntentDialog(stringLiteral: message))
    }
}

struct OpenAuraDashboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Aura Dashboard"
    static let description = IntentDescription("Opens the Aura Now Playing dashboard.")
    static var openAppWhenRun: Bool { true }

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .auraOpenSection,
            object: nil,
            userInfo: ["section": DashboardSection.nowPlaying.rawValue]
        )
        return .result()
    }
}

struct AuraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetAuraPrivateModeIntent(),
            phrases: ["Set Private Mode in \(.applicationName)"],
            shortTitle: "Set Private Mode",
            systemImageName: "eye.slash"
        )
        AppShortcut(
            intent: GetAuraPrivacyStatusIntent(),
            phrases: ["Check privacy in \(.applicationName)"],
            shortTitle: "Check Privacy",
            systemImageName: "checkmark.shield"
        )
        AppShortcut(
            intent: OpenAuraDashboardIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Dashboard",
            systemImageName: "music.note"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
