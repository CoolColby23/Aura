import Foundation

struct CompanionBuildConfiguration: Sendable {
    let apiKey: String
    let sharedSecret: String
    let cloudContainerIdentifier: String?

    static var current: CompanionBuildConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        return CompanionBuildConfiguration(
            apiKey: info["AuraLastFMAPIKey"] as? String ?? "",
            sharedSecret: info["AuraLastFMSharedSecret"] as? String ?? "",
            cloudContainerIdentifier: (info["AuraCloudContainer"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    var isLastFMConfigured: Bool { !apiKey.isEmpty && !sharedSecret.isEmpty }
    var isCloudConfigured: Bool { cloudContainerIdentifier?.isEmpty == false }
}

struct CompanionLastFMCredentials: Sendable {
    let apiKey: String
    let sharedSecret: String

    var isConfigured: Bool { !apiKey.isEmpty && !sharedSecret.isEmpty }
}
