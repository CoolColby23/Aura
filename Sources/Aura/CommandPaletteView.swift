import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = filteredCommands
        let selection = selectedID.flatMap { id in results.first { $0.id == id } } ?? results.first
        VStack(spacing: 0) {
            HStack(spacing: BrandMetrics.cardContentSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Go to a page, setting, or action", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .focused($searchFocused)
                    .onSubmit { run(selection) }
                    .onKeyPress(.downArrow) {
                        move(1, in: results, from: selection)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        move(-1, in: results, from: selection)
                        return .handled
                    }
                    .onChange(of: query) { _, _ in selectedID = nil }
                KeyCap(text: "esc")
            }
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.md)

            Rectangle().fill(BrandColors.hairline).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        if results.isEmpty {
                            AuraEmptyState(
                                symbol: "magnifyingglass",
                                title: "No results",
                                message: "Nothing matches “\(query)”. Try a page name, a setting, or an action like “private”."
                            )
                            .frame(minHeight: 280)
                        } else {
                            ForEach(groups(results), id: \.name) { group in
                                Text(group.name)
                                    .auraEyebrow()
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, BrandSpacing.sm)
                                    .padding(.top, BrandSpacing.sm)
                                    .padding(.bottom, 2)
                                ForEach(group.commands) { command in
                                    row(command, selected: command.id == selection?.id)
                                        .id(command.id)
                                }
                            }
                        }
                    }
                    .padding(BrandSpacing.sm)
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
            }

            Rectangle().fill(BrandColors.hairline).frame(height: 1)
            HStack(spacing: BrandSpacing.md) {
                hint(keys: "↑↓", label: "Move")
                hint(keys: "↩", label: "Open")
                Spacer()
                hint(keys: "⌘K", label: "Quick Open anywhere")
            }
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.sm)
        }
        .frame(width: 580, height: 480)
        .onAppear { searchFocused = true }
        .onExitCommand { dismiss() }
    }

    private func row(_ command: PaletteCommand, selected: Bool) -> some View {
        Button {
            run(command)
        } label: {
            HStack(spacing: BrandMetrics.cardContentSpacing) {
                SymbolTile(
                    symbol: command.symbol,
                    tint: selected ? theme.primaryColor : BrandColors.neutral,
                    size: BrandMetrics.tileMedium,
                    filled: selected
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.callout.weight(.semibold))
                    Text(command.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if selected {
                    KeyCap(text: "↩")
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 7)
            .background(
                selected ? theme.primaryColor.opacity(colorScheme == .dark ? 0.16 : 0.09) : Color.clear,
                in: .rect(cornerRadius: BrandRadius.sm, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { selectedID = command.id } }
        .accessibilityHint(selected ? "\(command.detail). Press Return to run." : command.detail)
    }

    private func hint(keys: String, label: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(text: keys)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private func run(_ command: PaletteCommand?) {
        guard let command else { return }
        command.action()
        dismiss()
    }

    private func move(_ offset: Int, in results: [PaletteCommand], from current: PaletteCommand?) {
        guard !results.isEmpty else { return }
        let index = current.flatMap { current in results.firstIndex { $0.id == current.id } } ?? 0
        let next = min(max(index + offset, 0), results.count - 1)
        selectedID = results[next].id
    }

    private struct ResultGroup {
        let name: String
        let commands: [PaletteCommand]
    }

    private func groups(_ commands: [PaletteCommand]) -> [ResultGroup] {
        var order: [String] = []
        var grouped: [String: [PaletteCommand]] = [:]
        for command in commands {
            if grouped[command.group] == nil { order.append(command.group) }
            grouped[command.group, default: []].append(command)
        }
        return order.map { ResultGroup(name: $0, commands: grouped[$0] ?? []) }
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
        var actions = [
            PaletteCommand(
                id: "privacy", title: model.isPrivate ? "End Private Mode" : "Go Private",
                detail: model.isPrivate ? "Resume Discord and Last.fm sharing" : "Pause Discord and Last.fm until you resume",
                group: "Actions", symbol: model.isPrivate ? "eye" : "eye.slash", keywords: "discord lastfm privacy"
            ) {
                model.isPrivate ? model.endPrivateMode() : model.setPrivate(until: nil)
            },
            PaletteCommand(
                id: "demo", title: model.demoModeEnabled ? "End Demo Playback" : "Start Demo Playback",
                detail: "Preview Now Playing with sample tracks, without publishing", group: "Actions",
                symbol: "testtube.2", keywords: "sample test music tour"
            ) { model.setDemoModeEnabled(!model.demoModeEnabled) },
        ]
        if model.snapshot.track != nil {
            actions.append(
                PaletteCommand(
                    id: "artwork", title: "Reload Album Artwork",
                    detail: "Clear the current cover and fetch it again", group: "Actions",
                    symbol: "photo.badge.arrow.down", keywords: "cover image retry repair"
                ) { model.retryCurrentArtwork() }
            )
        }
        let navigation = DashboardSection.allCases.filter { $0 != .settings }.map { section in
            PaletteCommand(
                id: "section.\(section.rawValue)", title: section.title,
                detail: "Go to \(section.title)", group: "Pages", symbol: section.symbol,
                keywords: section.rawValue
            ) { model.navigate(to: section) }
        }
        let settings = SettingsCategory.allCases.map { category in
            PaletteCommand(
                id: "settings.\(category.rawValue)", title: "\(category.rawValue) Settings",
                detail: category.detail, group: "Settings", symbol: category.symbol,
                keywords: "preferences configuration"
            ) { model.openSettings(category) }
        }
        return navigation + actions + settings
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
