import Foundation

enum ReleaseConfiguration {
    static var version: String {
        bundledValue(named: "CFBundleShortVersionString", fallback: "1.0.0")
    }
    static var build: String {
        bundledValue(named: "CFBundleVersion", fallback: "1")
    }

    static let discordApplicationID = bundledValue(
        named: "AURA_DISCORD_APPLICATION_ID",
        fallback: "1525555974390153346"
    )

    // Keep the fallback on the project site. Discord application icon hashes
    // can expire when the icon changes, leaving a cached 404 in profile cards.
    static let discordApplicationIconURL =
        "https://presence-fm.vercel.app/assets/brand/favicon-512.png"

    static var hasDiscordConfiguration: Bool { !discordApplicationID.isEmpty }

    private static func bundledValue(named name: String, fallback: String) -> String {
        if let environmentValue = ProcessInfo.processInfo.environment[name], !environmentValue.isEmpty { return environmentValue }
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: name) as? String, !bundleValue.isEmpty { return bundleValue }
        return fallback
    }
}
