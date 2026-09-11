import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: BrandMetrics.cardContentSpacing) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Open a page or run an action", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit {
                        guard let command = filteredCommands.first else { return }
                        command.action()
                        dismiss()
                    }
                Text("⌘K")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, BrandMetrics.capsuleHorizontal)
                    .padding(.vertical, BrandMetrics.capsuleVertical)
                    .background(.quaternary, in: .rect(cornerRadius: BrandRadius.xxs, style: .continuous))
            }
            .padding(BrandSpacing.md)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    if filteredCommands.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        let defaultCommandID = filteredCommands.first?.id
                        ForEach(filteredCommands) { command in
                            let isDefault = command.id == defaultCommandID
                            Button {
                                command.action()
                                dismiss()
                            } label: {
                                HStack(spacing: BrandMetrics.cardContentSpacing) {
                                    Image(systemName: command.symbol)
                                        .font(.callout.weight(.semibold))
                                        .frame(width: BrandMetrics.tileMedium, height: BrandMetrics.tileMedium)
                                        .background(.quaternary, in: .rect(cornerRadius: BrandRadius.tile(BrandMetrics.tileMedium), style: .continuous))
                                    VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                                        Text(command.title)
                                            .font(.callout.weight(.semibold))
                                        Text(command.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(command.group)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.tertiary)
                                    if isDefault {
                                        // Return runs the first match, so show
                                        // which row that is.
                                        Text("↩")
                                            .font(.caption.monospaced().weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, BrandMetrics.capsuleHorizontal)
                                            .padding(.vertical, BrandMetrics.capsuleVertical)
                                            .background(.quaternary, in: .rect(cornerRadius: BrandRadius.xxs, style: .continuous))
                                            .accessibilityLabel("Return")
                                    }
                                }
                                .padding(.horizontal, BrandSpacing.sm)
                                .padding(.vertical, BrandSpacing.sm)
                                .background(
                                    isDefault ? theme.readablePrimary(for: colorScheme).opacity(0.10) : Color.clear,
                                    in: .rect(cornerRadius: BrandRadius.sm, style: .continuous)
                                )
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(isDefault ? "\(command.detail). Press Return to run." : command.detail)
                        }
                    }
                }
                .padding(BrandSpacing.sm)
            }
        }
        .frame(width: 560, height: 500)
        .onAppear { searchFocused = true }
        .onExitCommand { dismiss() }
    }

    private var filteredCommands: [PaletteCommand] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return commands }
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return commands.filter { command in
            let haystack = "\(command.title) \(command.detail) \(command.group) \(command.keywords)".lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }

    private var commands: [PaletteCommand] {
        let navigation = DashboardSection.allCases.map { section in
            PaletteCommand(
                id: "section.\(section.rawValue)", title: section.title,
                detail: "Open \(section.title)", group: "Navigate", symbol: section.symbol,
                keywords: section.rawValue
            ) { model.navigate(to: section) }
        }
        let settings = SettingsCategory.allCases.map { category in
            PaletteCommand(
                id: "settings.\(category.rawValue)", title: category.rawValue,
                detail: category.detail, group: "Settings", symbol: category.symbol,
                keywords: "preferences configuration"
            ) { model.openSettings(category) }
        }
        var actions = [
            PaletteCommand(
                id: "privacy", title: model.isPrivate ? "End Private Mode" : "Go Private",
                detail: model.isPrivate ? "Resume Discord and Last.fm sharing" : "Pause external sharing until resumed",
                group: "Action", symbol: model.isPrivate ? "eye" : "eye.slash", keywords: "discord lastfm privacy"
            ) {
                model.isPrivate ? model.endPrivateMode() : model.setPrivate(until: nil)
            },
            PaletteCommand(
                id: "demo", title: model.demoModeEnabled ? "End Demo Playback" : "Start Demo Playback",
                detail: "Preview the Now Playing experience safely", group: "Action",
                symbol: "testtube.2", keywords: "sample test music"
            ) { model.setDemoModeEnabled(!model.demoModeEnabled) },
        ]
        if model.snapshot.track != nil {
            actions.append(
                PaletteCommand(
                    id: "artwork", title: "Reload Album Artwork",
                    detail: "Clear the current cover cache and fetch it again", group: "Action",
                    symbol: "photo.badge.arrow.down", keywords: "cover image retry repair"
                ) { model.retryCurrentArtwork() }
            )
        }
        return navigation + settings + actions
    }
}

private struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let detail: String
    let group: String
    let symbol: String
    let keywords: String
    let action: () -> Void
}
