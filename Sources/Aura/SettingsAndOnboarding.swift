import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var discordEnabled = false
    @State private var lastFMEnabled = false
    @State private var launchAtLogin = false
    @State private var selectedProviders = Set(PlaybackProviderID.allCases)
    @State private var hasLoadedPreferences = false
    @State private var notificationsRequested = false

    private let steps = ["Welcome", "Music Players", "Discord", "Last.fm", "Privacy", "In the Background", "Ready"]

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(spacing: 0) {
            topBar(preferences: preferences)
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.top, BrandSpacing.lg)

            ScrollView {
                stepContent
                    .frame(maxWidth: 500)
                    .padding(.horizontal, BrandSpacing.xl)
                    .padding(.vertical, BrandSpacing.lg)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 12)),
                                removal: .opacity
                            )
                    )
            }
            .scrollBounceBehavior(.basedOnSize)

            HStack {
                if step > 0 {
                    Button("Back") { go(to: step - 1) }
                        .auraButton()
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if step < steps.count - 1 {
                    Button(step == 0 ? "Get Started" : "Continue") { go(to: step + 1) }
                        .auraButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start Using Aura", action: finish)
                        .auraButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(BrandSpacing.lg)
        }
        .frame(width: 700, height: 580)
        .auraPanelBackground()
        .interactiveDismissDisabled(!preferences.onboardingComplete)
        .onAppear(perform: loadPreferences)
        .onExitCommand {
            if preferences.onboardingComplete {
                model.onboardingPresented = false
            } else if step > 0 {
                go(to: step - 1)
            }
        }
    }

    private func topBar(preferences: Preferences) -> some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? AnyShapeStyle(theme.liveGradient) : AnyShapeStyle(Color.primary.opacity(index < step ? 0.32 : 0.12)))
                        .frame(width: index == step ? 28 : 7, height: 7)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(steps.count): \(steps[step])")

            HStack {
                Spacer()
                if preferences.onboardingComplete {
                    Button("Close", systemImage: "xmark") { model.onboardingPresented = false }
                        .labelStyle(.iconOnly)
                        .auraButton()
                        .buttonBorderShape(.circle)
                        .help("Close the setup guide")
                        .accessibilityLabel("Close Onboarding")
                }
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private var stepContent: some View {
        @Bindable var model = model
        switch step {
        case 0:
            IntroStep(
                title: "Let’s give your music an aura.",
                text: "Aura carries the track you’re playing into Discord and Last.fm. Nothing is shared until you switch it on.",
                branded: true
            )
        case 1:
            IntroStep(
                title: "Which apps do you play music in?",
                symbol: "music.note",
                text: "Aura only watches the ones you pick. Apple Music asks for permission the first time."
            ) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BrandSpacing.sm) {
                    ForEach(PlaybackProviderID.allCases) { provider in
                        SelectableCard(
                            title: provider.displayName,
                            detail: providerDetail(provider),
                            isOn: providerBinding(provider)
                        )
                    }
                }
            }
        case 2:
            IntroStep(
                title: "Show it on Discord",
                symbol: "bubble.left.and.bubble.right.fill",
                text: "Your current track appears on your Discord profile while Discord Desktop is open."
            ) {
                OnboardingToggleRow(
                    symbol: "bubble.left.and.bubble.right",
                    title: "Share on Discord",
                    detail: ReleaseConfiguration.hasDiscordConfiguration
                        ? "You can fine-tune what appears in Settings."
                        : "This development build does not include Discord configuration.",
                    isOn: $discordEnabled
                )
                .disabled(!ReleaseConfiguration.hasDiscordConfiguration)
            }
        case 3:
            IntroStep(
                title: "Keep Last.fm in sync",
                symbol: "dot.radiowaves.left.and.right",
                text: "Add the API key and shared secret from your Last.fm API account, then authorize Aura in your browser."
            ) {
                VStack(spacing: BrandSpacing.sm) {
                    SecureField("API key", text: $model.credentialDraft.lastFMAPIKey)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Shared secret", text: $model.credentialDraft.lastFMSecret)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Authorize in Browser") { Task { await model.beginLastFMAuthorization() } }
                            .auraButton()
                            .disabled(
                                model.credentialDraft.lastFMAPIKey.isEmpty
                                    || model.credentialDraft.lastFMSecret.isEmpty
                            )
                        Button("I’ve Authorized") { Task { await model.completeLastFMAuthorization() } }
                            .auraButton()
                            .disabled(model.lastFMStatus != .connecting)
                        Spacer()
                    }
                    if !model.lastFMUsername.isEmpty {
                        Label("Connected as \(model.lastFMUsername)", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(BrandColors.success)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    OnboardingToggleRow(
                        symbol: "checkmark.seal",
                        title: "Scrobble finished listens",
                        detail: "Turns on once your account is connected. You can skip this for now.",
                        isOn: $lastFMEnabled
                    )
                    .padding(.top, BrandSpacing.xs)
                }
            }
        case 4:
            IntroStep(
                title: "Private whenever you want",
                symbol: "eye.slash.fill",
                text: "Go Private from the menu bar or the sidebar at any time — for 15 minutes, an hour, or until you resume."
            ) {
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    PrivacyPoint(symbol: "bubble.left.and.bubble.right", text: "Your Discord presence is cleared.")
                    PrivacyPoint(symbol: "dot.radiowaves.left.and.right", text: "Last.fm updates are paused.")
                    PrivacyPoint(symbol: "internaldrive", text: "History stays on this Mac, whether private or not.")
                }
                .padding(BrandMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .auraSurface()
            }
        case 5:
            IntroStep(
                title: "Quietly in the background",
                symbol: "menubar.rectangle",
                text: "Aura lives in your menu bar. It only notifies you when something needs you — lost permission, expired authorization, or a stuck queue."
            ) {
                VStack(spacing: BrandSpacing.sm) {
                    OnboardingToggleRow(
                        symbol: "power",
                        title: "Open at login",
                        detail: "Start Aura when you log in to this Mac.",
                        isOn: $launchAtLogin
                    )
                    HStack(spacing: BrandMetrics.cardContentSpacing) {
                        SymbolTile(symbol: "bell.badge", tint: theme.readablePrimary(for: colorScheme))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Notifications").font(.callout.weight(.semibold))
                            Text("Only for problems that need you.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(notificationsRequested ? "Requested" : "Allow…") {
                            notificationsRequested = true
                            Task { await model.requestNotifications() }
                        }
                        .auraButton()
                        .disabled(notificationsRequested)
                    }
                    .padding(BrandMetrics.cardPaddingCompact)
                    .auraSurface()
                }
            }
        default:
            IntroStep(
                title: "You’re all set",
                text: "Play a song in one of your music apps and Aura will pick it up. Connections can be changed or skipped at any time in Settings.",
                branded: true,
                sweeping: true
            )
        }
    }

    private func go(to newStep: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step = newStep }
    }

    private func providerDetail(_ provider: PlaybackProviderID) -> String {
        switch provider {
        case .appleMusic: "Built in"
        case .spotify: "Desktop app"
        case .youtubeMusic: "Through YTMDesktop"
        case .tidal: "Best effort"
        }
    }

    private func providerBinding(_ provider: PlaybackProviderID) -> Binding<Bool> {
        Binding(
            get: { selectedProviders.contains(provider) },
            set: { enabled in
                if enabled { selectedProviders.insert(provider) } else { selectedProviders.remove(provider) }
            }
        )
    }

    private func finish() {
        model.preferences.enabledPlaybackProviders = selectedProviders
        model.setDiscordEnabled(discordEnabled)
        model.setLastFMEnabled(lastFMEnabled && !model.lastFMUsername.isEmpty)
        model.preferences.launchAtLogin = launchAtLogin
        model.setLaunchAtLogin(launchAtLogin)
        model.completeOnboarding()
    }

    private func loadPreferences() {
        guard !hasLoadedPreferences else { return }
        let preferences = model.preferences
        selectedProviders = preferences.enabledPlaybackProviders
        discordEnabled = preferences.discordEnabled
        lastFMEnabled = preferences.lastFMEnabled
        launchAtLogin = preferences.launchAtLogin
        hasLoadedPreferences = true
    }
}

struct IntroStep<Controls: View>: View {
    let title: String
    var symbol: String = "sparkles"
    let text: String
    var branded = false
    var sweeping = false
    @ViewBuilder var controls: Controls
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            Group {
                if branded {
                    SweepingBrandMark(isPlaying: sweeping)
                        .frame(width: 104, height: 104)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(theme.primaryColor.gradient, in: .rect(cornerRadius: BrandRadius.tile(68), style: .continuous))
                        .shadow(color: theme.primaryColor.opacity(0.3), radius: 16, y: 6)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: BrandSpacing.sm) {
                Text(title)
                    .font(branded ? BrandTypography.heroTitle : BrandTypography.pageTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controls
                .padding(.top, BrandSpacing.xs)
        }
        .frame(maxWidth: .infinity)
    }
}

extension IntroStep where Controls == EmptyView {
    init(title: String, symbol: String = "sparkles", text: String, branded: Bool = false, sweeping: Bool = false) {
        self.init(title: title, symbol: symbol, text: text, branded: branded, sweeping: sweeping, controls: { EmptyView() })
    }
}

private struct SelectableCard: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? theme.readablePrimary(for: colorScheme) : Color.secondary.opacity(0.5))
            }
            .padding(BrandMetrics.cardPaddingCompact)
            .auraSurface(isOn ? .raised : .plain, radius: BrandRadius.sm)
            .overlay {
                RoundedRectangle(cornerRadius: BrandRadius.sm, style: .continuous)
                    .strokeBorder(isOn ? theme.readablePrimary(for: colorScheme).opacity(0.6) : .clear, lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { isOn.toggle() }
    }
}

private struct OnboardingToggleRow: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            SymbolTile(symbol: symbol, tint: theme.readablePrimary(for: colorScheme))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(BrandMetrics.cardPaddingCompact)
        .auraSurface()
    }
}

private struct PrivacyPoint: View {
    let symbol: String
    let text: String
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label {
            Text(text).font(.callout)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(theme.readablePrimary(for: colorScheme))
                .frame(width: 22)
        }
    }
}
