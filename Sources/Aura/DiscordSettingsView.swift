import SwiftUI

/// Discord settings, split by the question each group answers: is it on, what
/// will people see, which saved layout, and then the fine detail of text,
/// timing, images, and the link. The preview sits at the top so every change
/// below it is visible immediately.
struct DiscordSettingsSections: View {
    let model: AppModel
    let preferences: Preferences
    @State private var profileName = ""
    @State private var previewPaused = false

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Toggle("Share what you’re playing on Discord", isOn: $preferences.discordEnabled)
                .accessibilityIdentifier("discord.enabled")
                .onChange(of: preferences.discordEnabled) { _, value in model.setDiscordEnabled(value) }
            SettingsStatusRow(title: "Connection", detail: discordStatusExplanation, status: model.discordStatus)
            if preferences.discordEnabled {
                LabeledContent("Discord Desktop") {
                    HStack {
                        if model.discordStatus == .offline {
                            Button("Open Discord") { model.recoverDiscord() }
                                .accessibilityIdentifier("discord.open")
                        }
                        Button("Reconnect") { model.refreshDiscord() }
                            .disabled(model.discordStatus == .connecting)
                    }
                }
            }
        } header: {
            Text("Rich Presence")
        } footer: {
            Text("Keep Discord Desktop open and enable activity sharing under User Settings → Activity Privacy in Discord. Aura connects automatically; no Discord login is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("Discord activity sharing help", destination: URL(string: "https://support.discord.com/hc/en-us/articles/7931156448919-Activity-Sharing-on-Discord-FAQ")!)
        }

        Section {
            Picker("Preview playback", selection: $previewPaused) {
                Text("Playing").tag(false)
                Text("Paused").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("discord.preview-playback")
            if previewPaused && !preferences.discordSharePaused {
                Text("Aura hides your Discord activity while paused. Enable “Stay visible while paused” to share this preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            DiscordStatusPreview(
                firstLine: previewPresence.title,
                secondLine: previewPresence.state,
                activity: preferences.discordActivityType.rawValue,
                activityName: previewPresence.activityName,
                timer: previewPaused ? .hidden : preferences.discordTimerStyle,
                smallImage: preferences.discordSmallImage,
                buttonLabel: preferences.showLink ? (previewPresence.buttonLabel.isEmpty ? "Listen on Apple Music" : previewPresence.buttonLabel) : nil
            )
            Picker("Profile", selection: profileSelection) {
                if preferences.selectedDiscordProfileID == nil {
                    Text("Custom").tag(UUID?.none)
                }
                ForEach(preferences.availableDiscordProfiles) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            .accessibilityLabel("Discord presence profile")
            HStack {
                TextField("Save as", text: $profileName, prompt: Text("New profile name"))
                    .accessibilityIdentifier("discord.profile-name")
                Button("Save") {
                    if model.saveDiscordProfile(named: profileName) != nil { profileName = "" }
                }
                .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !preferences.discordPresenceProfiles.isEmpty {
                LabeledContent("Custom profiles") {
                    Menu("Delete…") {
                        ForEach(preferences.discordPresenceProfiles) { profile in
                            Button(profile.name, role: .destructive) { model.deleteDiscordProfile(id: profile.id) }
                        }
                    }
                    .fixedSize()
                }
            }
        } header: {
            Text("Preview")
        } footer: {
            Text("A preview with sample music. Profiles save the layout and sharing options below; built-in profiles are always available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Picker("Activity", selection: $preferences.discordActivityType) {
                ForEach(DiscordActivityType.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.activity-style")
            .onChange(of: preferences.discordActivityType) { _, _ in refresh() }
            TextField("Activity name", text: $preferences.discordActivityName, prompt: Text("Aura"))
                .accessibilityIdentifier("discord.activity-name")
                .onSubmit { refresh() }
            Picker("First line", selection: $preferences.discordLineOne) {
                ForEach(DiscordLineFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.first-line")
            .onChange(of: preferences.discordLineOne) { _, _ in refresh() }
            if preferences.discordLineOne == .custom {
                TextField("First line template", text: $preferences.discordCustomLineOne, prompt: Text("{title}"))
                    .onSubmit { refresh() }
            }
            Picker("Second line", selection: $preferences.discordLineTwo) {
                ForEach(DiscordLineFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.second-line")
            .onChange(of: preferences.discordLineTwo) { _, _ in refresh() }
            if preferences.discordLineTwo == .custom {
                TextField("Second line template", text: $preferences.discordCustomLineTwo, prompt: Text("{artist}"))
                    .onSubmit { refresh() }
            }
            Toggle("Include the album in formatted lines", isOn: $preferences.showAlbum)
                .onChange(of: preferences.showAlbum) { _, _ in refresh() }
        } header: {
            Text("Text")
        } footer: {
            Text(
                "The activity name follows “\(preferences.discordActivityType.rawValue)”. Templates can use {title}, {artist}, {album}, {platform}, {state}, {position}, and {duration}."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section {
            Picker("Timer", selection: $preferences.discordTimerStyle) {
                ForEach(DiscordTimerStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.timer")
            .onChange(of: preferences.discordTimerStyle) { _, _ in refresh() }
            Toggle("Stay visible while paused", isOn: $preferences.discordSharePaused)
                .accessibilityIdentifier("discord.share-paused")
                .onChange(of: preferences.discordSharePaused) { _, _ in refresh() }
            if preferences.discordSharePaused {
                TextField("Paused status", text: $preferences.discordPausedText, prompt: Text("Paused"))
                    .onSubmit { refresh() }
            }
        } header: {
            Text("Timing")
        } footer: {
            Text("Song progress includes the full track length. While paused, the song position stays fixed and the song progress bar disappears. Discord may show its own activity counter. Hidden turns off automatic timing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Picker("Large image", selection: $preferences.discordLargeImage) {
                ForEach(DiscordLargeImage.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.large-image")
            .onChange(of: preferences.discordLargeImage) { _, _ in refresh() }
            TextField("Large image hover text", text: $preferences.discordLargeImageText, prompt: Text("Optional"))
                .onSubmit { refresh() }
            Picker("Small image", selection: $preferences.discordSmallImage) {
                ForEach(DiscordSmallImage.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("discord.small-image")
            .onChange(of: preferences.discordSmallImage) { _, _ in refresh() }
            if preferences.discordSmallImage != .none {
                TextField("Small image hover text", text: $preferences.discordSmallImageText, prompt: Text("Automatic"))
                    .onSubmit { refresh() }
            }
        } header: {
            Text("Images")
        } footer: {
            Text("Album art uses the player’s cover first, then a matching Apple catalog cover. Aura’s icon appears on Discord when no public cover is available. Local artwork stays on your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle("Show a listening link", isOn: $preferences.showLink)
                .accessibilityIdentifier("discord.show-link")
                .onChange(of: preferences.showLink) { _, _ in refresh() }
            if preferences.showLink {
                TextField("Button label", text: $preferences.discordButtonLabel, prompt: Text("Automatic for each platform"))
                    .onSubmit { refresh() }
            }
        } header: {
            Text("Link")
        } footer: {
            Text("Discord limits button labels to 32 characters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var profileSelection: Binding<UUID?> {
        Binding(
            get: { preferences.selectedDiscordProfileID },
            set: { id in if let id { model.applyDiscordProfile(id: id) } }
        )
    }

    private var discordStatusExplanation: String {
        switch model.discordStatus {
        case .disabled: "Turn this on to show your current track on your Discord profile."
        case .inactive: "Discord is available. Aura shares when music starts."
        case .offline: "Discord Desktop is closed. Aura connects after you open it."
        case .connecting: "Connecting to Discord now."
        case .connected: "Your current track can appear on your profile."
        case .awaitingPermission: "Discord needs permission before Aura can connect."
        case .authorizationExpired: "Reconnect Discord to continue sharing."
        case .failed(let message): message
        }
    }

    private var previewPresence: DiscordPresence {
        let now = Date(timeIntervalSince1970: 2_000)
        let track = TrackMetadata(
            identity: .init(persistentID: "discord-preview"), title: "Midnight Drive",
            artist: "The Satellites", album: "Afterglow", duration: 224,
            source: .appleMusicCatalog, appleMusicURL: nil, artworkReference: nil
        )
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: now.addingTimeInterval(-82),
            accumulatedPlayTime: 82, lastPosition: 82, eligibility: .listening, outcome: .active
        )
        return DiscordPresenceFactory.make(
            session: session,
            snapshot: PlaybackSnapshot(track: track, state: previewPaused ? .paused : .playing, position: 82, observedAt: now, confidence: .high),
            preferences: preferences, artworkURL: nil, now: now
        )
    }

    private func refresh() { model.refreshPresenceOptions() }
}

/// A sample of how the presence will read. Deliberately drawn in Aura's own
/// language rather than imitating Discord's interface.
private struct DiscordStatusPreview: View {
    let firstLine: String
    let secondLine: String
    let activity: String
    let activityName: String
    let timer: DiscordTimerStyle
    let smallImage: DiscordSmallImage
    let buttonLabel: String?
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("\(activity) \(activityName)")
                .auraEyebrow()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: BrandMetrics.cardContentSpacing) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: BrandRadius.xs, style: .continuous)
                        .fill(LinearGradient(colors: [theme.secondaryColor, theme.primaryColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Text("MD")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    if smallImage != .none {
                        BrandMark()
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .background(.background, in: .circle)
                            .offset(x: 5, y: 5)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(firstLine).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(secondLine).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    if let timerText {
                        Text(timerText).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let buttonLabel {
                Text(buttonLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.primary.opacity(0.07), in: .rect(cornerRadius: BrandRadius.xs, style: .continuous))
            }
        }
        .padding(BrandMetrics.cardPaddingCompact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .auraSurface(.inset, radius: BrandRadius.sm)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("discord.preview")
        .accessibilityLabel("Discord preview: \(activity) \(activityName), \(firstLine), \(secondLine), \(timer.rawValue)")
    }

    private var timerText: String? {
        switch timer {
        case .progress: "1:22 / 3:44"
        case .elapsed: "1:22 elapsed"
        case .remaining: "2:22 left"
        case .hidden: nil
        }
    }
}
